import FNMNCore
import Foundation
import Observation
import os

/// Intervals that show in Instruments' Points of Interest: loading the library and opening a material.
enum Signposts {
    static let library = OSSignposter(subsystem: "local.fnmn.reader", category: .pointsOfInterest)
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
    var failure: String?
    let storageURL: URL
    private let file: LibraryFile
    private var lastWrite: Task<Void, Never>?
    /// Saved places wait here: a reader saves one at every paragraph, and nothing on screen shows them.
    @ObservationIgnored private var places: [ProgressChange] = []
    @ObservationIgnored private var progressWrite: Task<Void, Never>?
    @ObservationIgnored private var progressUnsaved = false

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
            await relinkCloudFolder()
            loadState = .ready
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
        } catch {
            failure = error.localizedDescription
        }
    }

    /// A saved place is published with the next other progress change or with the write; every other change
    /// is published at once. The write follows two seconds after the last change.
    func apply(_ change: ProgressChange) {
        if case .savePosition = change {
            places.append(change)
        } else {
            progress = (places + [change]).reduce(progress) { $0.applying($1) }
            places = []
        }
        progressUnsaved = true
        progressWrite?.cancel()
        progressWrite = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await saveProgress()
        }
    }

    /// Writes progress now: when the app leaves the foreground and when a reader closes.
    func saveProgress() async {
        progressWrite?.cancel()
        guard progressUnsaved else { return }
        if !places.isEmpty {
            progress = places.reduce(progress) { $0.applying($1) }
            places = []
        }
        progressUnsaved = false
        do {
            try await file.saveProgress(progress)
        } catch {
            failure = error.localizedDescription
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

    /// Stores a picked prepared package, book folder, or the FNMN folder. Reading it happens in `LibraryFile`,
    /// off the main thread. The FNMN folder becomes the library's home: materials stay there and the app keeps
    /// only its catalog, covers and state. Each delivery comes down from iCloud once to be read, and its copy on
    /// the device is dropped again, so the phone never holds the whole folder.
    func importFile(at url: URL, onStep: @escaping @MainActor (ImportStep) -> Void) async throws {
        let catalog = url.appending(path: "catalog.json")
        guard CloudFolder.contains(catalog) else {
            try await CloudFolder.download(url)
            try await write(saving: false) { [file] snapshot in try await file.storePicked(url, into: snapshot) }
            return
        }
        try await link(url)
        onStep(.downloadingFromCloud)
        try await CloudFolder.download(catalog)
        try await CloudFolder.download(url.appending(path: "index.json"))
        let deliveries = try await CloudFolder.files(in: url.appending(path: "deliveries"), withExtension: "tar")
        try await write(saving: false) { [file] snapshot in
            var next = try await file.applyBrowserCatalog(from: url, into: snapshot)
            for (index, delivery) in deliveries.enumerated() {
                onStep(.importing(index, of: deliveries.count))
                try await CloudFolder.download(delivery)
                next = try await file.addCloudDelivery(delivery, into: next)
                CloudFolder.evict(delivery)
            }
            next = try await file.placeLinks(from: url, into: next)
            try await file.save(next, previous: snapshot)
            return next
        }
        let books = url.appending(path: "books")
        onStep(.downloadingFromCloud)
        try await CloudFolder.download(books)
        try await write(saving: false) { [file] snapshot in try await file.storeBooks(in: books, into: snapshot) }
    }

    func storeVideoFile(_ itemID: String, from download: URL) async throws {
        try await write(saving: false) { [file] snapshot in try await file.storeVideoFile(itemID, from: download, into: snapshot) }
    }

    func videoFile(_ itemID: String) -> URL? {
        snapshot.videoFiles[itemID].map { LibraryFile.videoFile(root: storageURL, name: $0) }
    }

    func articleFile(_ materialID: String, path: String) -> URL? {
        LibraryFile.articleFile(root: storageURL, materialID: materialID, path: path, revision: snapshot.articleRevisions[materialID])
    }

    func coverFile(_ materialID: String) -> URL {
        LibraryFile.coverFile(root: storageURL, materialID: materialID)
    }

    /// Where an article's pictures resolve: its unpacked copy for a material in iCloud, its revision otherwise.
    func articleFolder(_ materialID: String) -> URL {
        if let entry = entry(materialID), entry.delivery != nil { return file.cachedFolder(of: entry) }
        return LibraryFile.articleFolder(root: storageURL, materialID: materialID, revision: snapshot.articleRevisions[materialID])
    }

    func bookFolder(_ directoryName: String) -> URL {
        LibraryFile.bookFolder(root: storageURL, directoryName: directoryName)
    }

    /// A material in iCloud is unpacked from its copy in the cache; when the system has emptied that, its
    /// archive comes down from iCloud first, which needs a connection if the phone has dropped its copy.
    func article(_ materialID: String) async throws -> ImportPackage {
        guard let entry = entry(materialID), entry.delivery != nil else {
            return try await file.article(materialID, revision: snapshot.articleRevisions[materialID])
        }
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

    private func link(_ folder: URL) async throws {
        UserDefaults.standard.set(try folder.bookmarkData(), forKey: Self.cloudFolderKey)
        _ = folder.startAccessingSecurityScopedResource()
        await file.useCloudFolder(folder)
    }

    private func relinkCloudFolder() async {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.cloudFolderKey) else { return }
        var isStale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            failure = LibraryError.cloudFolderMissing.localizedDescription
            return
        }
        _ = folder.startAccessingSecurityScopedResource()
        if isStale, let fresh = try? folder.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: Self.cloudFolderKey)
        }
        await file.useCloudFolder(folder)
    }

    func bookText(_ record: BookRecord) async throws -> String {
        try await file.bookText(directoryName: record.directoryName, contentFile: record.metadata.contentFile)
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
