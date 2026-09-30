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
@MainActor @Observable
final class LibraryModel {
    private(set) var snapshot = LibrarySnapshot()
    private(set) var progress = ReadingProgress()
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
    private var lastWrite: Task<Void, Never>?
    /// Saved places wait here: a reader saves one at every paragraph, and nothing on screen shows them.
    @ObservationIgnored private var places: [ProgressChange] = []
    @ObservationIgnored private var progressWrite: Task<Void, Never>?
    @ObservationIgnored private var progressUnsaved = false
    /// This device's changes waiting to be appended to its journal, and what it knows of the other journals.
    @ObservationIgnored private var journal: [JournalEvent] = []
    @ObservationIgnored private var sync = JournalSync()
    @ObservationIgnored private let device: String = {
        if let id = UserDefaults.standard.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "deviceID")
        return id
    }()

    init(
        storageURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "FNMN"),
        cacheURL: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "FNMN")
    ) {
        self.storageURL = storageURL
        file = LibraryFile(url: storageURL, cache: cacheURL)
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
            sync = try await file.loadSync()
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
        do {
            try await write(saving: true) { snapshot in try snapshot.applying(change) }
            record(.library(change))
            scheduleSave()
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
            progress = (places + [change]).reduce(progress) { $0.applying($1) }
            places = []
        }
        switch change {
        case .open, .setRead, .readThrough: record(.progress(change))
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
                if case let .savePosition(_, itemID, _) = change { latest[itemID] = change }
            }
            progress = places.reduce(progress) { $0.applying($1) }
            places = []
            for change in latest.values { record(.progress(change)) }
        }
        progressUnsaved = false
        let events = journal
        journal = []
        do {
            try await file.saveProgress(progress)
            try await file.appendJournal(events, device: device)
            try await file.saveSync(sync)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Takes in the other devices' changes: at launch, when the app comes back, and when the FNMN folder is linked.
    func syncWithOtherDevices() async {
        await readOriginals()
        guard let folder = await file.journalFolder(), FileManager.default.fileExists(atPath: folder.path) else { return }
        do {
            try await CloudFolder.download(folder, timeout: .seconds(60))
            await saveProgress()
            let unread = try await file.unreadJournalEvents(except: device, sync: sync)
            guard unread.applied != sync.applied else { return }
            sync.applied = unread.applied
            try await write(saving: true) { [self] snapshot in
                let merged = merge(unread.events, into: snapshot, progress, sync: sync)
                progress = merged.progress
                sync = merged.sync
                return merged.catalog
            }
            try await file.saveProgress(progress)
            try await file.saveSync(sync)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func record(_ change: JournalEvent.Change) {
        for event in JournalEvent.events(for: change, at: .now) {
            sync.record(event)
            journal.append(event)
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

    /// Stores a delivery archive the Mac prepared, with its pictures and videos, reading it off the main thread.
    func store(archive: URL) async throws {
        try await write(saving: false) { [file] snapshot in try await file.storeArticle(archive: archive, into: snapshot) }
    }

    /// Stores what was picked with `+` → File, anywhere: it is copied into the FNMN folder. Picking the FNMN
    /// folder itself reads it again. Reading happens in `LibraryFile`, off the main thread.
    func importFile(at url: URL, onStep: @escaping @MainActor (ImportStep) -> Void) async throws {
        guard let folder = cloudFolder else { throw LibraryError.cloudFolderMissing }
        if url.standardizedFileURL == folder.standardizedFileURL {
            try await readLibraryFolder(onStep: onStep)
            return
        }
        try await CloudFolder.download(url)
        try await write(saving: false) { [file] snapshot in try await file.storePicked(url, into: snapshot) }
    }

    /// Makes the FNMN folder the library's home: what an older version kept in the app moves there, then
    /// the folder is read and the other devices' journals are taken in.
    func linkLibraryFolder(_ folder: URL, onStep: @escaping @MainActor (ImportStep) -> Void) async throws {
        UserDefaults.standard.set(try folder.bookmarkData(), forKey: Self.cloudFolderKey)
        _ = folder.startAccessingSecurityScopedResource()
        await file.useCloudFolder(folder)
        cloudFolder = folder
        try await moveIntoCloudIfNeeded()
        try await readLibraryFolder(onStep: onStep)
        await syncWithOtherDevices()
    }

    /// Reads the FNMN folder: its catalog, then each delivery, which comes down from iCloud once to be read
    /// and is let go again, so the phone never holds the whole folder.
    private func readLibraryFolder(onStep: @escaping @MainActor (ImportStep) -> Void) async throws {
        guard let folder = cloudFolder else { throw LibraryError.cloudFolderMissing }
        onStep(.downloadingFromCloud)
        let catalog = folder.appending(path: "catalog.json")
        if CloudFolder.contains(catalog) {
            try await CloudFolder.download(catalog)
            try await CloudFolder.download(folder.appending(path: "index.json"))
            let deliveries = try await CloudFolder.files(in: folder.appending(path: "deliveries"), withExtension: "tar")
            try await write(saving: false) { [file] snapshot in
                var next = try await file.applyBrowserCatalog(from: folder, into: snapshot)
                for (index, delivery) in deliveries.enumerated() {
                    onStep(.importing(index, of: deliveries.count))
                    try await CloudFolder.download(delivery)
                    next = try await file.addCloudDelivery(delivery, into: next)
                    CloudFolder.evict(delivery)
                }
                next = try await file.placeLinks(from: folder, into: next)
                try await file.save(next, previous: snapshot)
                return next
            }
        }
    }

    private func moveIntoCloudIfNeeded() async throws {
        guard await file.holdsMaterialsInApp(snapshot) else { return }
        try await write(saving: false) { [file] snapshot in try await file.moveIntoCloud(snapshot) }
    }

    // MARK: Originals

    /// What Open Original shows: the page the material was made from, or else its file in `originals/`.
    func original(of itemID: String, page: URL?) -> Original? {
        if let page { return .web(page) }
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
        guard let folder = cloudFolder?.appending(path: "originals"),
              let files = try? await CloudFolder.files(in: folder) else { return }
        originals = Dictionary(files.map { ($0.deletingPathExtension().lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func coverFile(_ materialID: String) -> URL {
        LibraryFile.coverFile(root: storageURL, materialID: materialID)
    }

    /// Where an article's pictures resolve: its unpacked copy.
    func articleFolder(_ materialID: String) -> URL? {
        entry(materialID).map(file.cachedFolder(of:))
    }

    /// Whether opening the material has to bring its archive down from iCloud first.
    func needsDownload(_ materialID: String) async -> Bool {
        guard let entry = entry(materialID) else { return false }
        return await !file.isUnpacked(entry)
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

    private func entry(_ materialID: String) -> ArticleEntry? {
        snapshot.articles.first { $0.material.id == materialID }
    }

    /// The FNMN folder is outside the app, so access to it is kept as a security-scoped bookmark and taken
    /// again at every launch; the app holds it for as long as it runs.
    private static let cloudFolderKey = "cloudFolderBookmark"

    private func relinkCloudFolder() async {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.cloudFolderKey) else { return }
        var isStale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else { return }
        _ = folder.startAccessingSecurityScopedResource()
        if isStale, let fresh = try? folder.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: Self.cloudFolderKey)
        }
        await file.useCloudFolder(folder)
        cloudFolder = folder
        do {
            try await moveIntoCloudIfNeeded()
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
            if saving { try await file.save(updated, previous: current) }
            snapshot = updated
            for change in updated.progressChanges(since: current) { apply(change) }
        }
        lastWrite = Task { _ = try? await task.value }
        try await task.value
    }
}
