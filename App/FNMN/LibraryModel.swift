import Foundation
import Observation

enum LibraryLoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

@MainActor @Observable
final class LibraryModel {
    var snapshot = LibrarySnapshot()
    var loadState: LibraryLoadState = .loading
    var operationError: String?
    var pendingShare: URL?
    var storageURL: URL { file.root }
    private let file: LibraryFile

    init(file: LibraryFile? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.file = file ?? LibraryFile(url: base.appending(path: "FNMN"))
    }

    func load() async {
        loadState = .loading
        do {
            snapshot = try await file.load()
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
            return
        }
        guard let runtime = Bundle.main.url(forResource: "MarkdownRuntime", withExtension: nil) else { return }
        do { try await file.installRuntime(from: runtime) }
        catch { operationError = error.localizedDescription }
    }

    func importData(_ data: Data) async throws {
        let package = try JSONDecoder().decode(ImportPackage.self, from: data)
        let previous = snapshot
        try snapshot.importPackage(package)
        let sourceFolder = package.material.kind == .video ? CaptureSource.youtube.folderName : CaptureSource.web.folderName
        snapshot.place(materialID: package.material.id, in: sourceFolder)
        do { try await persist() }
        catch { snapshot = previous; throw error }
    }

    func storeArticle(_ package: ImportPackage, files: [String: Data]) async throws {
        let previous = snapshot
        try snapshot.importPackage(package)
        snapshot.place(materialID: package.material.id, in: CaptureSource.web.folderName)
        do {
            try await file.saveArticleFiles(files, materialID: package.material.id)
            try await persist()
        } catch {
            snapshot = previous
            try? await file.removeArticleFiles(materialID: package.material.id)
            throw error
        }
    }

    func importPickedDocument(from url: URL) async throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            try await importBook(from: url)
            return
        }
        if url.pathExtension.lowercased() == "pdf" {
            throw CaptureError.unprepared(.pdf)
        }
        guard url.pathExtension.lowercased() == "json" else {
            throw CaptureError.unrecognizedDocument
        }
        try await importData(Data(contentsOf: url))
    }

    func importBook(from directory: URL) async throws {
        let imported = try BookCatalog.inspect(from: directory)
        let previous = snapshot
        let replacing = previous.books.contains { $0.id == imported.record.id }
        snapshot.importBook(imported.record)
        snapshot.place(materialID: imported.record.id, in: CaptureSource.pdf.folderName)
        do {
            try await file.copyBook(from: directory, named: imported.record.directoryName)
            try await file.saveState(snapshot)
        } catch {
            snapshot = previous
            if !replacing {
                try await file.removeBook(named: imported.record.directoryName)
            }
            throw error
        }
    }

    func recordOpening(materialID: String, at date: Date = .now) async {
        let previous = snapshot.readings[materialID]
        snapshot.recordOpening(materialID: materialID, at: date)
        do { try await file.saveState(snapshot) }
        catch {
            snapshot.readings[materialID] = previous
            operationError = error.localizedDescription
        }
    }

    func setRead(_ isRead: Bool, materialID: String) async {
        let previous = snapshot.readings[materialID]
        snapshot.setRead(isRead, materialID: materialID)
        do { try await file.saveState(snapshot) }
        catch {
            snapshot.readings[materialID] = previous
            operationError = error.localizedDescription
        }
    }

    func save(position: ReadingPosition, materialID: String) async {
        let previous = snapshot.positions[materialID]
        snapshot.positions[materialID] = position
        do { try await file.saveState(snapshot) }
        catch {
            snapshot.positions[materialID] = previous
            operationError = error.localizedDescription
        }
    }

    func saveVideoTime(_ seconds: Double, materialID: String, blockID: String) async {
        let previous = snapshot.positions[materialID]
        guard snapshot.recordVideoTime(materialID: materialID, blockID: blockID, seconds: seconds) else { return }
        do { try await file.saveState(snapshot) }
        catch {
            snapshot.positions[materialID] = previous
            operationError = error.localizedDescription
        }
    }

    func save(note text: String, materialID: String, blockID: String) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let previous = snapshot.notes
        if let index = snapshot.notes.firstIndex(where: { $0.materialID == materialID && $0.blockID == blockID }) {
            snapshot.notes[index].text = text
        } else {
            snapshot.notes.append(Note(materialID: materialID, blockID: blockID, text: text))
        }
        do { try await file.saveState(snapshot) }
        catch {
            snapshot.notes = previous
            throw error
        }
    }

    func addFolder(_ name: String) async {
        guard !name.isEmpty else { return }
        let previous = snapshot.folders
        snapshot.folders = Array(Set(snapshot.folders + [name])).sorted()
        do { try await file.saveState(snapshot) }
        catch {
            snapshot.folders = previous
            operationError = error.localizedDescription
        }
    }

    func renameFolder(from name: String, to newName: String) async {
        let previous = snapshot
        guard snapshot.renameFolder(from: name, to: newName) else {
            operationError = "Choose a new album name that is not already used."
            return
        }
        do { try await persist() }
        catch {
            snapshot = previous
            operationError = error.localizedDescription
        }
    }

    func move(materialID: String, to folder: String) async {
        let previous = snapshot
        snapshot.move(materialID: materialID, to: folder)
        do { try await persist() }
        catch {
            snapshot = previous
            operationError = error.localizedDescription
        }
    }

    private func persist() async throws {
        try await file.save(snapshot)
    }
}

struct ArticleClient {
    let endpoint: URL
    let token: String
    let allowsInsecureLAN: Bool

    func prepare(url: URL, folder: String?) async throws -> (ImportPackage, [String: Data]) {
        let isLocalhost = endpoint.host == "127.0.0.1" || endpoint.host == "localhost"
        guard endpoint.scheme == "https" || isLocalhost || allowsInsecureLAN else {
            throw URLError(.secureConnectionFailed)
        }
        var request = URLRequest(url: endpoint.appending(path: "articles"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ArticleRequest(url: url, folders: folder.map { [$0] } ?? []))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard 200 ..< 300 ~= http.statusCode else {
            let detail = (try? JSONDecoder().decode(FailureBody.self, from: data))?.detail
            throw ArticleServiceError.rejected(detail ?? String(decoding: data, as: UTF8.self))
        }
        let delivery = try JSONDecoder().decode(ArticleDelivery.self, from: data)
        return (delivery.package, delivery.files)
    }

    private struct ArticleRequest: Encodable { let url: URL; let folders: [String] }
    private struct FailureBody: Decodable { let detail: String }
}

private enum ArticleServiceError: Error, LocalizedError {
    case rejected(String)

    var errorDescription: String? {
        guard case let .rejected(message) = self else { return nil }
        return message
    }
}

private struct ArticleDelivery: Decodable {
    let package: ImportPackage
    let files: [String: Data]

    init(from decoder: Decoder) throws {
        package = try ImportPackage(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let encoded = try container.decodeIfPresent([String: String].self, forKey: .files) ?? [:]
        var files: [String: Data] = [:]
        for (path, value) in encoded {
            guard let data = Data(base64Encoded: value) else {
                throw DecodingError.dataCorruptedError(forKey: .files, in: container, debugDescription: path)
            }
            files[path] = data
        }
        self.files = files
    }

    private enum CodingKeys: String, CodingKey { case files }
}
