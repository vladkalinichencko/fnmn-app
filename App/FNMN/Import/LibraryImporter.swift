import FNMNCore
import Foundation

@MainActor
final class LibraryImporter {
    typealias Write = (
        _ saving: Bool, _ next: @escaping @MainActor (LibrarySnapshot) async throws -> LibrarySnapshot
    ) async throws -> Void

    private let file: LibraryFile

    init(file: LibraryFile) {
        self.file = file
    }

    func store(archive: URL, write: Write) async throws {
        try await write(false) { [file] snapshot in try await file.storeArticle(archive: archive, into: snapshot) }
    }

    func storeLink(_ url: URL, write: Write) async throws {
        try await write(false) { [file] snapshot in try await file.storeMade(.link(url), into: snapshot) }
    }

    func storeFile(_ picked: URL, write: Write) async throws -> String {
        let package = try await file.package(ofFile: picked)
        try await write(false) { [file] snapshot in try await file.storeMade(package, into: snapshot) }
        return package.material.id
    }

    func adopt(_ folder: URL) async throws {
        _ = folder.startAccessingSecurityScopedResource()
        UserDefaults.standard.set(try folder.bookmarkData(), forKey: Self.cloudFolderKey)
        await file.useCloudFolder(folder)
    }

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

    func moveIntoCloudIfNeeded(_ snapshot: LibrarySnapshot, write: Write) async throws {
        guard await file.holdsMaterialsInApp(snapshot) else {
            return
        }
        try await write(false) { [file] snapshot in try await file.moveIntoCloud(snapshot) }
    }

    func readFolder(
        _ folder: URL, onStep: @escaping @MainActor (ImportStep) -> Void, write: @escaping Write
    ) async throws {
        onStep(.readingLibraryFolder)
        let catalog = folder.appending(path: "catalog.json")
        if CloudFolder.contains(catalog) {
            try await CloudFolder.download(catalog)
            try await write(true) { [file] snapshot in try await file.applyBrowserCatalog(from: folder, into: snapshot) }
        }
        try await readChangedDeliveries(in: folder, onStep: onStep, write: write)
    }

    func readChangedDeliveries(
        in folder: URL?, onStep: @escaping @MainActor (ImportStep) -> Void = { _ in }, write: @escaping Write
    ) async throws {
        let target = LibraryDeliveries(file: file, write: write, onStep: onStep)
        let failures = await DeliverySync.run(target, in: folder)
        guard failures.isEmpty else {
            throw DeliverySyncError.failed(failures.joined(separator: "; "))
        }
    }

    func originalFiles(in folder: URL) async throws -> [String: URL] {
        let files = try await CloudFolder.files(in: folder)
        return Dictionary(files.map { ($0.deletingPathExtension().lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static let cloudFolderKey = "cloudFolderBookmark"
}

@MainActor
private final class LibraryDeliveries: DeliveryTarget {
    let subfolder = "deliveries"
    private let file: LibraryFile
    private let write: LibraryImporter.Write
    private let onStep: @MainActor (ImportStep) -> Void

    init(file: LibraryFile, write: @escaping LibraryImporter.Write, onStep: @escaping @MainActor (ImportStep) -> Void) {
        self.file = file
        self.write = write
        self.onStep = onStep
    }

    func changed(_ archives: [URL]) async throws -> [URL] {
        var changed: [URL] = []
        try await write(true) { [file] snapshot in
            let found = try await file.changedDeliveries(archives, in: snapshot)
            changed = found.deliveries
            return found.snapshot
        }
        return changed
    }

    func add(_ archive: URL, index: Int, total: Int) async throws {
        onStep(.reading(index, of: total))
        try await write(true) { [file] snapshot in try await file.addCloudDelivery(archive, into: snapshot) }
    }

    func finish(_ archives: [URL]) async throws {
    }
}
