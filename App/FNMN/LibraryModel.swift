import Foundation
import Observation

enum LibraryLoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

enum Preparation: Equatable {
    case idle
    case working(String)
    case choosing(String)
    case failed(String)
}

@MainActor @Observable
final class LibraryModel {
    var snapshot = LibrarySnapshot()
    var loadState: LibraryLoadState = .loading
    var operationError: String?
    var preparation: Preparation = .idle
    var macConnection: MacConnection?
    var storageURL: URL { file.root }
    private let file: LibraryFile
    private let connectionStore: any MacConnectionStorage
    private let macService: any MacServicePort
    private var isLoading = false
    private var lastMutation: Task<Void, Never>?

    init(
        file: LibraryFile? = nil,
        connectionStore: any MacConnectionStorage = KeychainMacConnectionStore(),
        macService: any MacServicePort = ArticleClient()
    ) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.file = file ?? LibraryFile(url: base.appending(path: "FNMN"))
        self.connectionStore = connectionStore
        self.macService = macService
        self.macConnection = connectionStore.load()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        loadState = .loading
        do {
            snapshot = try await file.load()
            let corrupt = await file.corruptPackageNames
            loadState = .ready
            if !corrupt.isEmpty {
                operationError = "Couldn't read \(corrupt.joined(separator: ", ")). The rest of the library is open."
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func importData(_ data: Data) async throws -> String {
        let package = try JSONDecoder().decode(ImportPackage.self, from: data)
        return try await serializedMutation {
            self.snapshot = try await self.file.storeArticle(package, files: [:], into: self.snapshot)
            return package.material.id
        }
    }

    func storeArticle(_ package: ImportPackage, files: [String: Data]) async throws -> String {
        try await serializedMutation {
            self.snapshot = try await self.file.storeArticle(package, files: files, into: self.snapshot)
            return package.material.id
        }
    }

    func importPickedDocument(from url: URL) async throws -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return try await importBook(from: url)
        }
        if url.pathExtension.lowercased() == "pdf" {
            throw CaptureError.unprepared(.pdf)
        }
        guard url.pathExtension.lowercased() == "json" else {
            throw CaptureError.unrecognizedDocument
        }
        return try await importData(Data(contentsOf: url))
    }

    func importBook(from directory: URL) async throws -> String {
        let imported = try BookCatalog.inspect(from: directory)
        return try await serializedMutation {
            self.snapshot = try await self.file.storeBook(imported.record, from: directory, into: self.snapshot)
            return imported.record.id
        }
    }

    func importBrowserLibrary(from directory: URL) async throws {
        try await serializedMutation {
            self.snapshot = try await self.file.storeBrowserLibrary(from: directory, into: self.snapshot)
        }
    }

    func saveMacConnection(_ connection: MacConnection) throws {
        try connectionStore.save(connection)
        macConnection = connection
    }

    func checkMacConnection() async throws {
        guard let macConnection else { throw MacConnectionError.notConfigured }
        try await macService.check(connection: macConnection)
    }

    func prepareLink(url: URL) async {
        guard acceptsPreparation else { return }
        guard let macConnection else {
            preparation = .failed(MacConnectionError.notConfigured.localizedDescription)
            return
        }
        preparation = .working("Fetching the page")
        ImportActivity.start(title: url.host ?? "Article", status: "Fetching the page")
        do {
            let (package, files) = try await macService.prepare(url: url, folder: nil, connection: macConnection)
            preparation = .working("Saving")
            await ImportActivity.update(status: "Saving", fraction: 0.8)
            let materialID = try await storeArticle(package, files: files)
            await ImportActivity.end(status: "Ready")
            preparation = .choosing(materialID)
        } catch {
            await ImportActivity.end(status: "Failed")
            preparation = .failed(error.localizedDescription)
        }
    }

    func prepareFile(at url: URL) async {
        guard acceptsPreparation else { return }
        preparation = .working("Saving")
        ImportActivity.start(title: url.lastPathComponent, status: "Saving")
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            if FileManager.default.fileExists(atPath: url.appending(path: "catalog.json").path) {
                try await importBrowserLibrary(from: url)
                await ImportActivity.end(status: "Ready")
                preparation = .idle
                return
            }
            let materialID = try await importPickedDocument(from: url)
            await ImportActivity.end(status: "Ready")
            preparation = .choosing(materialID)
        } catch {
            await ImportActivity.end(status: "Failed")
            preparation = .failed(error.localizedDescription)
        }
    }

    func finishPreparation() {
        preparation = .idle
    }

    private var acceptsPreparation: Bool {
        switch preparation {
        case .idle, .failed: true
        case .working, .choosing: false
        }
    }

    func assign(materialID: String, to folders: [String]) async {
        await commit { $0.assign(materialID: materialID, to: folders) }
    }

    func recordOpening(materialID: String, at date: Date = .now) async {
        await commit { $0.recordOpening(materialID: materialID, at: date) }
    }

    func setRead(_ isRead: Bool, materialID: String) async {
        await commit { $0.setRead(isRead, materialID: materialID) }
    }

    func save(position: ReadingPosition, materialID: String, progress: Double) async {
        await commit {
            $0.positions[materialID] = position
            $0.setProgress(progress, materialID: materialID)
        }
    }

    func annotate(materialID: String, piece: Int, quote: String, caption: String?, mark: TextMark?) async {
        await commit {
            $0.highlights = applyingAnnotation(
                to: $0.highlights,
                materialID: materialID,
                piece: piece,
                quote: quote,
                caption: caption,
                mark: mark
            )
        }
    }

    func setArchived(_ isArchived: Bool, materialID: String) async {
        await commit { $0.setArchived(isArchived, materialID: materialID) }
    }

    func saveVideoTime(_ seconds: Double, materialID: String, blockID: String) async {
        await commit { _ = $0.recordVideoTime(materialID: materialID, blockID: blockID, seconds: seconds) }
    }

    func addFolder(_ name: String) async {
        guard !name.isEmpty else { return }
        await commit { $0.folders = Array(Set($0.folders + [name])).sorted() }
    }

    func renameFolder(from name: String, to newName: String) async {
        do {
            try await serializedMutation {
                var next = self.snapshot
                guard next.renameFolder(from: name, to: newName) else {
                    self.operationError = "Choose a new album name that is not already used."
                    return
                }
                try await self.file.saveState(next)
                self.snapshot = next
            }
        } catch {
            operationError = error.localizedDescription
        }
    }

    func place(materialID: String, in folder: String) async {
        await commit { $0.place(materialID: materialID, in: folder) }
    }

    private func commit(_ change: @escaping (inout LibrarySnapshot) -> Void) async {
        do {
            try await serializedMutation {
                var next = self.snapshot
                change(&next)
                guard next != self.snapshot else { return }
                try await self.file.saveState(next)
                self.snapshot = next
            }
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func serializedMutation<T: Sendable>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = lastMutation
        let task = Task { @MainActor in
            await previous?.value
            return try await operation()
        }
        lastMutation = Task { @MainActor in _ = try? await task.value }
        return try await task.value
    }
}
