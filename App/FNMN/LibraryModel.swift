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
    var pendingShare: URL?
    var preparation: Preparation = .idle
    var openMaterialID: String?
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
        }
    }

    func importData(_ data: Data) async throws -> String {
        let decoded = try JSONDecoder().decode(ImportPackage.self, from: data)
        let package = ImportPackage(material: decoded.material, sections: decoded.sections, blocks: decoded.blocks, body: decoded.body)
        let previous = snapshot
        try snapshot.importPackage(package)
        do {
            try await persist()
            return package.material.id
        } catch {
            snapshot = previous
            throw error
        }
    }

    func storeArticle(_ package: ImportPackage, files: [String: Data]) async throws -> String {
        let stored = ImportPackage(material: package.material, sections: package.sections, blocks: package.blocks, body: package.body)
        let previous = snapshot
        try snapshot.importPackage(stored)
        do {
            try await file.saveArticleFiles(files, materialID: stored.material.id)
            try await persist()
            return stored.material.id
        } catch {
            snapshot = previous
            try? await file.removeArticleFiles(materialID: stored.material.id)
            throw error
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
        let previous = snapshot
        let replacing = previous.books.contains { $0.id == imported.record.id }
        snapshot.importBook(imported.record)
        do {
            try await file.copyBook(from: directory, named: imported.record.directoryName)
            try await file.saveState(snapshot)
            return imported.record.id
        } catch {
            snapshot = previous
            if !replacing {
                try await file.removeBook(named: imported.record.directoryName)
            }
            throw error
        }
    }

    func prepareYouTube(url: URL) async {
        guard acceptsPreparation else { return }
        preparation = .working("Opening the video")
        ImportActivity.start(title: url.host ?? "YouTube", status: "Opening the video")
        do {
            let package = try await YouTubeImport.package(for: url)
            preparation = .working("Saving")
            await ImportActivity.update(status: "Saving", fraction: 0.8)
            let materialID = try await storeArticle(package, files: [:])
            await ImportActivity.end(status: "Ready")
            preparation = .choosing(materialID)
        } catch {
            await ImportActivity.end(status: "Failed")
            preparation = .failed(error.localizedDescription)
        }
    }

    func prepareLink(url: URL, endpoint: URL, token: String, allowsInsecureLAN: Bool) async {
        guard acceptsPreparation else { return }
        preparation = .working("Fetching the page")
        ImportActivity.start(title: url.host ?? "Article", status: "Fetching the page")
        do {
            let (package, files) = try await ArticleClient(endpoint: endpoint, token: token, allowsInsecureLAN: allowsInsecureLAN)
                .prepare(url: url, folder: nil)
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
        let previous = snapshot
        snapshot.assign(materialID: materialID, to: folders)
        do { try await persist() }
        catch {
            snapshot = previous
            operationError = error.localizedDescription
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

    func save(position: ReadingPosition, materialID: String, progress: Double) async {
        let previousPosition = snapshot.positions[materialID]
        let previousReading = snapshot.readings[materialID]
        snapshot.positions[materialID] = position
        snapshot.setProgress(progress, materialID: materialID)
        do { try await file.saveState(snapshot) }
        catch {
            snapshot.positions[materialID] = previousPosition
            snapshot.readings[materialID] = previousReading
            operationError = error.localizedDescription
        }
    }

    func annotate(materialID: String, piece: Int, quote: String, caption: String?, mark: TextMark?) async {
        let trimmedQuote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuote.isEmpty || !(trimmedCaption ?? "").isEmpty else { return }
        let previous = snapshot.highlights
        if let index = snapshot.highlights.firstIndex(where: { $0.materialID == materialID && $0.piece == piece }) {
            if !trimmedQuote.isEmpty { snapshot.highlights[index].quote = trimmedQuote }
            if let trimmedCaption, !trimmedCaption.isEmpty { snapshot.highlights[index].caption = trimmedCaption }
            if let mark { snapshot.highlights[index].mark = mark }
        } else {
            snapshot.highlights.append(
                Highlight(
                    materialID: materialID,
                    piece: piece,
                    quote: trimmedQuote,
                    caption: trimmedCaption ?? "",
                    mark: mark
                )
            )
        }
        do { try await file.saveState(snapshot) }
        catch {
            snapshot.highlights = previous
            operationError = error.localizedDescription
        }
    }

    func setArchived(_ isArchived: Bool, materialID: String) async {
        let previous = snapshot.archived
        snapshot.setArchived(isArchived, materialID: materialID)
        do { try await file.saveState(snapshot) }
        catch {
            snapshot.archived = previous
            operationError = error.localizedDescription
        }
    }

    func open(_ materialID: String) {
        openMaterialID = materialID
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
