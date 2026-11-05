import FNMNCore
import Foundation

/// Everything that comes into the library from outside: a link or file kept as it is, the delivery archive
/// the server prepared, and the FNMN folder in iCloud Drive — its catalog, its deliveries and the move of
/// what an older version kept inside the app. The importer is a mechanism without state: the catalog changes
/// go back through the model's serialized write, passed in with every call.
@MainActor
final class LibraryImporter {
    /// The model's write into the catalog, one change after another: `LibraryModel.write`.
    typealias Write = (
        _ saving: Bool, _ next: @escaping @MainActor (LibrarySnapshot) async throws -> LibrarySnapshot
    ) async throws -> Void

    private let file: LibraryFile

    init(file: LibraryFile) {
        self.file = file
    }

    /// Stores a delivery archive the server prepared, with its pictures and videos, in the place of the link
    /// or file it was made from. The archive is read in `LibraryFile`, off the main thread.
    func store(archive: URL, write: Write) async throws {
        try await write(false) { [file] snapshot in try await file.storeArticle(archive: archive, into: snapshot) }
    }

    /// A link kept as it is, the card that shows it until the server prepares the page.
    func storeLink(_ url: URL, write: Write) async throws {
        try await write(false) { [file] snapshot in try await file.storeMade(.link(url), into: snapshot) }
    }

    /// A picked file kept as it is, known by its bytes; the file itself goes into `originals/` beside the
    /// delivery through the model, which looks the material's entry up in the catalog. Returns the material's id.
    func storeFile(_ picked: URL, write: Write) async throws -> String {
        let package = try await file.package(ofFile: picked)
        try await write(false) { [file] snapshot in try await file.storeMade(package, into: snapshot) }
        return package.material.id
    }

    /// Makes the FNMN folder the library's home: access to it is kept as a security-scoped bookmark and
    /// taken at once, so the app holds it for as long as it runs.
    func adopt(_ folder: URL) async throws {
        _ = folder.startAccessingSecurityScopedResource()
        UserDefaults.standard.set(try folder.bookmarkData(), forKey: Self.cloudFolderKey)
        await file.useCloudFolder(folder)
    }

    /// The linked folder at launch: the bookmark taken again, refreshed when stale; nil before the reader
    /// has pointed to the folder once.
    func relinkedFolder() async -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.cloudFolderKey) else {
            return nil
        }
        var isStale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        _ = folder.startAccessingSecurityScopedResource()
        if isStale, let fresh = try? folder.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: Self.cloudFolderKey)
        }
        await file.useCloudFolder(folder)
        return folder
    }

    /// The first time the FNMN folder is linked, what an older version kept inside the app moves there.
    func moveIntoCloudIfNeeded(_ snapshot: LibrarySnapshot, write: Write) async throws {
        guard await file.holdsMaterialsInApp(snapshot) else {
            return
        }
        try await write(false) { [file] snapshot in try await file.moveIntoCloud(snapshot) }
    }

    /// Reads the FNMN folder: its catalog, then every delivery this device has not read as it is now.
    func readFolder(
        _ folder: URL, onStep: @escaping @MainActor (ImportStep) -> Void, write: Write
    ) async throws {
        onStep(.readingLibraryFolder)
        let catalog = folder.appending(path: "catalog.json")
        if CloudFolder.contains(catalog) {
            try await CloudFolder.download(catalog)
            try await write(true) { [file] snapshot in try await file.applyBrowserCatalog(from: folder, into: snapshot) }
        }
        try await readChangedDeliveries(in: folder, onStep: onStep, write: write)
    }

    /// Takes in the deliveries this device has not read as it is now: all of them on the first read,
    /// later the ones other devices added or rewrote. The device that asked the server for a material stores
    /// it first; the others get it here from iCloud. Each one is saved as soon as it is read, so it shows as
    /// a card at once and a read that stops goes on from there the next time.
    func readChangedDeliveries(
        in folder: URL?, onStep: @MainActor (ImportStep) -> Void = { _ in }, write: Write
    ) async throws {
        let deliveries = try await deliveryFiles(in: folder)
        var changed: [URL] = []
        try await write(true) { [file] snapshot in
            let found = try await file.changedDeliveries(deliveries, in: snapshot)
            changed = found.deliveries
            return found.snapshot
        }
        for (index, delivery) in changed.enumerated() {
            onStep(.reading(index, of: changed.count))
            try await CloudFolder.download(delivery)
            try await write(true) { [file] snapshot in try await file.addCloudDelivery(delivery, into: snapshot) }
        }
    }

    private func deliveryFiles(in folder: URL?) async throws -> [URL] {
        guard let folder, CloudFolder.contains(folder.appending(path: "deliveries")) else {
            return []
        }
        return try await CloudFolder.files(in: folder.appending(path: "deliveries"), withExtension: "tar")
    }

    /// The files materials were made from and saved videos, in the FNMN folder's `originals/`, by the name
    /// of the delivery each belongs to.
    func originalFiles(in folder: URL) async throws -> [String: URL] {
        let files = try await CloudFolder.files(in: folder)
        return Dictionary(files.map { ($0.deletingPathExtension().lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The FNMN folder is outside the app, so access to it is kept as a security-scoped bookmark.
    private static let cloudFolderKey = "cloudFolderBookmark"
}
