import FNMNCore
import Foundation
import Observation
import os

enum Signposts {
    static let library = OSSignposter(subsystem: "local.fnmn.reader", category: .pointsOfInterest)
}

enum Original: Equatable {
    case web(URL)
    case file(URL)
}

enum LibraryPhase: Equatable {
    case loading
    case needsFolder
    case ready
    case failed(String)
}

@MainActor @Observable
final class LibraryModel {
    private(set) var snapshot = LibrarySnapshot()
    private(set) var progress = ReadingProgress()
    private(set) var queries = LibraryQueries(LibrarySnapshot())
    private(set) var loadState = LoadState.idle

    var phase: LibraryPhase {
        switch loadState {
        case .idle, .loading: .loading
        case let .failed(message): .failed(message)
        case .ready: cloudFolder == nil ? .needsFolder : .ready
        }
    }
    private(set) var cloudFolder: URL?
    private(set) var originals: [String: URL] = [:]
    var previewedOriginal: URL?
    var failure: String?
    let storageURL: URL
    private let file: LibraryFile
    private let importer: LibraryImporter
    private let journal: JournalSync
    private var lastWrite: Task<Void, Never>?
    @ObservationIgnored private var places: [ProgressChange] = []
    @ObservationIgnored private var progressWrite: Task<Void, Never>?
    @ObservationIgnored private var progressUnsaved = false
    @ObservationIgnored private var journalRead: Task<Void, Never>?
    @ObservationIgnored private var reindex: Task<Void, Never>?

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

    var deviceID: String {
        journal.device
    }

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
                await removeDeleted(deleted)
            }
        } catch {
            failure = error.localizedDescription
        }
    }

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

    func saveProgress() async {
        progressWrite?.cancel()
        guard progressUnsaved else { return }
        foldPlaces()
        progressUnsaved = false
        do {
            try await file.saveProgress(progress)
            try await journal.flush()
        } catch {
            progressUnsaved = true
            failure = error.localizedDescription
        }
    }

    private func foldPlaces() {
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

    func syncWithOtherDevices() async {
        await readJournals()
        await readOriginals()
        do {
            try await importer.readChangedDeliveries(in: cloudFolder, write: self.write)
        } catch {
            failure = error.localizedDescription
        }
        reindex = Task { await reindexSearch() }
    }

    func reindexSearch() async {
        guard cloudFolder != nil else {
            return
        }
        for entry in snapshot.articles {
            guard entry.material.kind != .video, await !file.hasSearchBody(entry.material.id) else {
                continue
            }
            _ = try? await article(entry.material.id)
        }
        searchIndex = nil
    }

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

    func position(of itemID: String) -> ReadingPosition? {
        for case let .savePosition(position, id, _) in places.reversed() where id == itemID {
            return position
        }
        return progress.positions[itemID]
    }

    private func refreshQueries() {
        queries = LibraryQueries(snapshot)
    }

    func store(archive: URL) async throws {
        try await importer.store(archive: archive, write: self.write)
    }

    func storeLink(_ url: URL) async throws {
        try await importer.storeLink(url, write: self.write)
    }

    func storeFile(_ picked: URL) async throws -> String {
        let materialID = try await importer.storeFile(picked, write: self.write)
        try await storeOriginal(picked, of: materialID)
        return materialID
    }

    func linkLibraryFolder(_ folder: URL, onStep: @escaping @MainActor (ImportStep) -> Void) async throws {
        try await importer.adopt(folder)
        cloudFolder = folder
        try await importer.moveIntoCloudIfNeeded(snapshot, write: self.write)
        try await importer.readFolder(folder, onStep: onStep, write: self.write)
        await readOriginals()
        await syncWithOtherDevices()
    }


    func original(of itemID: String, page: URL?) -> Original? {
        if let page {
            return .web(page)
        }
        return originalFile(itemID).map(Original.file)
    }

    func originalFile(_ itemID: String) -> URL? {
        entry(itemID)?.originalStem.flatMap { originals[$0] }
    }

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

    func articleFolder(_ materialID: String) -> URL? {
        entry(materialID).map(file.cachedFolder(of:))
    }

    func article(_ materialID: String) async throws -> ImportPackage {
        guard let entry = entry(materialID) else { throw LibraryError.cloudFolderMissing }
        if await !file.isUnpacked(entry) {
            guard let archive = await file.deliveryURL(of: entry) else { throw LibraryError.cloudFolderMissing }
            try await CloudFolder.download(archive, timeout: .seconds(120))
        }
        return try await file.openCloudArticle(entry)
    }

    @ObservationIgnored private var searchIndex: SearchIndex?

    func search(_ query: String) async -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return []
        }
        if searchIndex == nil {
            searchIndex = await SearchIndex.load(bodies: (try? await file.searchBodies()) ?? [:])
        }
        guard let searchIndex else {
            return []
        }
        return await searchIndex.hits(
            query: needle,
            articles: snapshot.articles,
            annotations: snapshot.annotations,
            addedAt: snapshot.addedAt
        ) {
            MarkedMarkdown.plainText($0, baseURL: nil)
        }
    }

    func recordReadingMode(_ event: ReadingModeEvent) async {
        try? await file.appendReadingMode(event, device: journal.device)
    }

    private func deletedMaterial(in change: LibraryChange) -> (entry: ArticleEntry, original: URL?)? {
        guard case let .delete(itemID) = change, let entry = entry(itemID) else { return nil }
        return (entry, originalFile(itemID))
    }

    private func removeDeleted(_ deleted: (entry: ArticleEntry, original: URL?)) async {
        try? await file.removeDelivery(of: deleted.entry)
        await file.removeSearchBody(deleted.entry.material.id)
        if let original = deleted.original {
            try? await file.removeOriginal(original)
        }
        await readOriginals()
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
