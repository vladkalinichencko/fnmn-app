import FNMNCore
import Foundation
import Observation
import os

/// Intervals that show in Instruments' Points of Interest: loading the library and opening a material.
enum Signposts {
    static let library = OSSignposter(subsystem: "local.fnmn.reader", category: .pointsOfInterest)
}

/// Where a material came from: the page it was made from, or else the file, kept in the FNMN folder.
enum Original: Equatable {
    case web(URL)
    case file(URL)
}

enum LibraryLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

/// The one owner of the library: every change goes through `apply`, is written to disk, then published.
/// The catalog and reading progress are separate properties, so a view that reads one never wakes for the other.
/// The journal lives in `JournalSync` and importing in `LibraryImporter`; the model sequences both and owns
/// what the screens read.
@MainActor @Observable
final class LibraryModel {
    private(set) var snapshot = LibrarySnapshot()
    private(set) var progress = ReadingProgress()
    private(set) var queries = LibraryQueries(LibrarySnapshot())
    private(set) var loadState = LibraryLoadState.idle
    /// The FNMN folder in iCloud Drive, where every material lives; until the reader points to it once,
    /// the app asks for it instead of showing the library.
    private(set) var cloudFolder: URL?
    /// The files materials were made from and saved videos, in the FNMN folder's `originals/`, by the name of
    /// the delivery each belongs to; read again with the other devices' changes.
    private(set) var originals: [String: URL] = [:]
    /// An original file being shown in Quick Look.
    var previewedOriginal: URL?
    var failure: String?
    let storageURL: URL
    private let file: LibraryFile
    private let importer: LibraryImporter
    private let journal: JournalSync
    private var lastWrite: Task<Void, Never>?
    /// Saved places wait here: a reader saves one at every paragraph, and nothing on screen shows them.
    @ObservationIgnored private var places: [ProgressChange] = []
    @ObservationIgnored private var progressWrite: Task<Void, Never>?
    @ObservationIgnored private var progressUnsaved = false
    @ObservationIgnored private var journalRead: Task<Void, Never>?

    init(
        storageURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "FNMN"),
        cacheURL: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "FNMN")
    ) {
        self.storageURL = storageURL
        let file = LibraryFile(url: storageURL, cache: cacheURL)
        self.file = file
        importer = LibraryImporter(file: file)
        journal = JournalSync(file: file)
    }

    /// This device's id, written once by the journal; the digest's engagement journal is named by it too.
    var deviceID: String {
        journal.device
    }

    /// Every window asks for the library; only the first ask, or a retry after a failure, reads it.
    func load() async {
        switch loadState {
        case .loading, .ready: return
        case .idle, .failed: break
        }
        loadState = .loading
        let interval = Signposts.library.beginInterval("Load library")
        defer { Signposts.library.endInterval("Load library", interval) }
        do {
            (snapshot, progress) = try await file.load()
            refreshQueries()
            try await journal.load()
            await relinkCloudFolder()
            loadState = .ready
            await syncWithOtherDevices()
            let corrupt = await file.corruptPackageNames
            if !corrupt.isEmpty {
                failure = "Couldn’t read \(corrupt.joined(separator: ", ")). The rest of the library is open."
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func apply(_ change: LibraryChange) async {
        let deleted = deletedMaterial(in: change)
        do {
            try await write(saving: true) { snapshot in try snapshot.applying(change) }
            journal.record(.library(change))
            scheduleSave()
            if let deleted {
                try? await file.removeDelivery(of: deleted.entry)
                if let original = deleted.original {
                    try? await file.removeOriginal(original)
                }
                await readOriginals()
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    /// A saved place is published with the next other progress change or with the write; every other change
    /// is published at once. The write follows two seconds after the last change. A place starting over or
    /// forgotten follows from this device's own catalog, so it stays out of the journal.
    func apply(_ change: ProgressChange) {
        if case .savePosition = change {
            places.append(change)
        } else {
            let next = (places + [change]).reduce(progress) { $0.applying($1) }
            places = []
            if next != progress {
                progress = next
            }
        }
        switch change {
        case .open, .openGroup, .setRead, .readThrough, .line, .fold, .reset: journal.record(.progress(change))
        case .savePosition, .restart, .forget: break
        }
        scheduleSave()
    }

    /// Writes progress and this device's journal now: when the app leaves the foreground and when a reader closes.
    /// Of the places saved since the last write, only the last one of each material goes into the journal.
    func saveProgress() async {
        progressWrite?.cancel()
        guard progressUnsaved else { return }
        if !places.isEmpty {
            var latest: [String: ProgressChange] = [:]
            for change in places {
                if case let .savePosition(_, itemID, _) = change {
                    latest[itemID] = change
                }
            }
            progress = places.reduce(progress) { $0.applying($1) }
            places = []
            for change in latest.values {
                journal.record(.progress(change))
            }
        }
        progressUnsaved = false
        do {
            try await file.saveProgress(progress)
            try await journal.flush()
        } catch {
            progressUnsaved = true
            failure = error.localizedDescription
        }
    }

    /// Takes in the other devices' changes: at launch, when the app comes back, and when the FNMN folder is linked.
    /// Their journals come first, because notes, marks, albums and deletions are a few lines, while the deliveries
    /// can take minutes to come down from iCloud; a delivery of a material deleted elsewhere is then not read in.
    func syncWithOtherDevices() async {
        await readJournals()
        await readOriginals()
        do {
            try await importer.readChangedDeliveries(in: cloudFolder, write: self.write)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// The other devices' journals. A launch and a return to the app can both start a sync, and two reads at once
    /// would apply the same lines twice, so a read that finds one running waits for it instead.
    private func readJournals() async {
        if let running = journalRead {
            return await running.value
        }
        let read = Task { await readJournalsOnce() }
        journalRead = read
        await read.value
        journalRead = nil
    }

    private func readJournalsOnce() async {
        guard let folder = await journal.folderToRead() else {
            return
        }
        do {
            try await CloudFolder.download(folder, timeout: .seconds(60))
            await saveProgress()
            guard let events = try await journal.unread() else {
                return
            }
            try await write(saving: true) { [self] snapshot in
                let merged = journal.merging(events, into: snapshot, progress)
                progress = merged.progress
                return merged.catalog
            }
            try await file.saveProgress(progress)
            try await journal.save()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func scheduleSave() {
        progressUnsaved = true
        progressWrite?.cancel()
        progressWrite = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await saveProgress()
        }
    }

    /// Where a reader opens, including a place that is not published yet.
    func position(of itemID: String) -> ReadingPosition? {
        for case let .savePosition(position, id, _) in places.reversed() where id == itemID {
            return position
        }
        return progress.positions[itemID]
    }

    /// Rebuilds the queries the screens read; the only place `LibraryQueries` is built.
    private func refreshQueries() {
        queries = LibraryQueries(snapshot)
    }

    /// Stores a delivery archive the server prepared, with its pictures and videos, in the place of the link
    /// or file it was made from. The archive is read in `LibraryFile`, off the main thread.
    func store(archive: URL) async throws {
        try await importer.store(archive: archive, write: self.write)
    }

    /// A link kept as it is, the card that shows it until the server prepares the page.
    func storeLink(_ url: URL) async throws {
        try await importer.storeLink(url, write: self.write)
    }

    /// A picked file kept as it is, with the file itself in `originals/`, until the server makes a material of it;
    /// returns the material's id.
    func storeFile(_ picked: URL) async throws -> String {
        let materialID = try await importer.storeFile(picked, write: self.write)
        try await storeOriginal(picked, of: materialID)
        return materialID
    }

    /// Makes the FNMN folder the library's home: what an older version kept in the app moves there, then
    /// the folder is read and the other devices' journals are taken in.
    func linkLibraryFolder(_ folder: URL, onStep: @escaping @MainActor (ImportStep) -> Void) async throws {
        try await importer.adopt(folder)
        cloudFolder = folder
        try await importer.moveIntoCloudIfNeeded(snapshot, write: self.write)
        try await importer.readFolder(folder, onStep: onStep, write: self.write)
        await readOriginals()
        await syncWithOtherDevices()
    }

    // MARK: Originals

    /// What Open Original shows: the page the material was made from, or else its file in `originals/`.
    func original(of itemID: String, page: URL?) -> Original? {
        if let page {
            return .web(page)
        }
        return originalFile(itemID).map(Original.file)
    }

    /// A video saved for the system player is the video's original file.
    func originalFile(_ itemID: String) -> URL? {
        entry(itemID)?.originalStem.flatMap { originals[$0] }
    }

    /// Copies a file the material was made from, or a downloaded video, into `originals/`.
    func storeOriginal(_ download: URL, of itemID: String) async throws {
        guard let entry = entry(itemID) else { throw LibraryError.cloudFolderMissing }
        try await file.storeOriginal(download, of: entry)
        await readOriginals()
    }

    func removeOriginal(of itemID: String) async {
        guard let original = originalFile(itemID) else { return }
        do {
            try await file.removeOriginal(original)
        } catch {
            failure = error.localizedDescription
        }
        await readOriginals()
    }

    /// Brings the file down from iCloud, then shows it in Quick Look.
    func preview(_ original: URL) async {
        do {
            try await CloudFolder.download(original, timeout: .seconds(300))
            previewedOriginal = original
        } catch {
            failure = error.localizedDescription
        }
    }

    private func readOriginals() async {
        guard let folder = cloudFolder?.appending(path: "originals") else {
            return
        }
        guard let files = try? await importer.originalFiles(in: folder) else {
            return
        }
        originals = files
    }

    func coverFile(_ materialID: String) -> URL {
        LibraryFile.coverFile(root: storageURL, materialID: materialID)
    }

    /// Where an article's pictures resolve: its unpacked copy.
    func articleFolder(_ materialID: String) -> URL? {
        entry(materialID).map(file.cachedFolder(of:))
    }

    /// A material is unpacked from its copy in the cache; when the system has emptied that, its archive comes
    /// down from iCloud first, which needs a connection if the phone has let its copy go.
    func article(_ materialID: String) async throws -> ImportPackage {
        guard let entry = entry(materialID) else { throw LibraryError.cloudFolderMissing }
        if await !file.isUnpacked(entry) {
            guard let archive = await file.deliveryURL(of: entry) else { throw LibraryError.cloudFolderMissing }
            try await CloudFolder.download(archive, timeout: .seconds(120))
        }
        return try await file.openCloudArticle(entry)
    }

    /// The entry and saved original of the material a change deletes, taken before it goes from the catalog.
    private func deletedMaterial(in change: LibraryChange) -> (entry: ArticleEntry, original: URL?)? {
        guard case let .delete(itemID) = change, let entry = entry(itemID) else { return nil }
        return (entry, originalFile(itemID))
    }

    private func entry(_ materialID: String) -> ArticleEntry? {
        snapshot.articles.first { $0.material.id == materialID }
    }

    private func relinkCloudFolder() async {
        guard let folder = await importer.relinkedFolder() else {
            return
        }
        cloudFolder = folder
        do {
            try await importer.moveIntoCloudIfNeeded(snapshot, write: self.write)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Writes run one after another, each on the snapshot the previous one produced.
    /// Imports save their own files, so only reader changes are saved here. A material that left
    /// or got a new text loses its reading progress in the same step.
    private func write(saving: Bool, _ next: @escaping @MainActor (LibrarySnapshot) async throws -> LibrarySnapshot) async throws {
        let previous = lastWrite
        let task = Task { @MainActor in
            await previous?.value
            let current = snapshot
            let updated = try await next(current)
            guard updated != current else { return }
            if saving {
                try await file.save(updated, previous: current)
            }
            snapshot = updated
            refreshQueries()
            for change in updated.progressChanges(since: current) { apply(change) }
        }
        lastWrite = Task { _ = try? await task.value }
        try await task.value
    }
}
