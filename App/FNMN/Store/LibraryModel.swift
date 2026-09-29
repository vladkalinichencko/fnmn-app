import FNMNCore
import Foundation
import Observation

enum LibraryLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

/// The one owner of the library: every change goes through `apply`, is written to disk, then published.
@MainActor @Observable
final class LibraryModel {
    private(set) var snapshot = LibrarySnapshot()
    private(set) var loadState = LibraryLoadState.idle
    var failure: String?
    let storageURL: URL
    private let file: LibraryFile
    private var lastWrite: Task<Void, Never>?

    init(storageURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "FNMN")) {
        self.storageURL = storageURL
        file = LibraryFile(url: storageURL)
    }

    /// Every window asks for the library; only the first ask, or a retry after a failure, reads it.
    func load() async {
        switch loadState {
        case .loading, .ready: return
        case .idle, .failed: break
        }
        loadState = .loading
        do {
            snapshot = try await file.load()
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

    /// Stores a package the Mac prepared, with its pictures and videos.
    func store(_ package: ImportPackage, files: [String: Data]) async throws {
        try await write(saving: false) { [file] snapshot in try await file.storeArticle(package, files: files, into: snapshot) }
    }

    /// Stores a picked prepared package, book folder, or the FNMN folder: a prepared browser library
    /// (`catalog.json`, `deliveries/`) with its books in `books/`.
    func importFile(at url: URL) async throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CaptureError.unrecognizedDocument
        }
        if isDirectory.boolValue {
            try await CloudFolder.download(url)
        }
        if isDirectory.boolValue, FileManager.default.fileExists(atPath: url.appending(path: "catalog.json").path) {
            try await write(saving: false) { [file] snapshot in try await file.storeBrowserLibrary(from: url, into: snapshot) }
            for book in try bookFolders(in: url.appending(path: "books")) {
                try await importFile(at: book)
            }
        } else if isDirectory.boolValue {
            let record = try BookCatalog.inspect(from: url).record
            try await write(saving: false) { [file] snapshot in try await file.storeBook(record, from: url, into: snapshot) }
        } else if url.pathExtension.lowercased() == "json" {
            let package = try JSONDecoder().decode(ImportPackage.self, from: Data(contentsOf: url))
            try await store(package, files: [:])
        } else if url.pathExtension.lowercased() == "pdf" {
            throw CaptureError.unprepared(.pdf)
        } else {
            throw CaptureError.unrecognizedDocument
        }
    }

    private func bookFolders(in folder: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
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

    func articleFolder(_ materialID: String) -> URL {
        LibraryFile.articleFolder(root: storageURL, materialID: materialID, revision: snapshot.articleRevisions[materialID])
    }

    func bookFolder(_ directoryName: String) -> URL {
        LibraryFile.bookFolder(root: storageURL, directoryName: directoryName)
    }

    func bookText(_ record: BookRecord) async throws -> String {
        try await file.bookText(directoryName: record.directoryName, contentFile: record.metadata.contentFile)
    }

    /// Writes run one after another, each on the snapshot the previous one produced.
    /// Imports save their own files, so only reader changes are saved here.
    private func write(saving: Bool, _ next: @escaping @MainActor (LibrarySnapshot) async throws -> LibrarySnapshot) async throws {
        let previous = lastWrite
        let task = Task { @MainActor in
            await previous?.value
            let current = snapshot
            let updated = try await next(current)
            guard updated != current else { return }
            if saving { try await file.save(updated, previous: current) }
            snapshot = updated
        }
        lastWrite = Task { _ = try? await task.value }
        try await task.value
    }
}
