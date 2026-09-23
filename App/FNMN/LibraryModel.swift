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
        snapshot = try await file.storeArticle(package, files: [:], into: snapshot)
        return package.material.id
    }

    func storeArticle(_ package: ImportPackage, files: [String: Data]) async throws -> String {
        snapshot = try await file.storeArticle(package, files: files, into: snapshot)
        return package.material.id
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
        snapshot = try await file.storeBook(imported.record, from: directory, into: snapshot)
        return imported.record.id
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

    func open(_ materialID: String) {
        openMaterialID = materialID
    }

    func saveVideoTime(_ seconds: Double, materialID: String, blockID: String) async {
        await commit { _ = $0.recordVideoTime(materialID: materialID, blockID: blockID, seconds: seconds) }
    }

    func addFolder(_ name: String) async {
        guard !name.isEmpty else { return }
        await commit { $0.folders = Array(Set($0.folders + [name])).sorted() }
    }

    func renameFolder(from name: String, to newName: String) async {
        var next = snapshot
        guard next.renameFolder(from: name, to: newName) else {
            operationError = "Choose a new album name that is not already used."
            return
        }
        do {
            try await file.saveState(next)
            snapshot = next
        } catch {
            operationError = error.localizedDescription
        }
    }

    func place(materialID: String, in folder: String) async {
        await commit { $0.place(materialID: materialID, in: folder) }
    }

    private func commit(_ change: (inout LibrarySnapshot) -> Void) async {
        var next = snapshot
        change(&next)
        guard next != snapshot else { return }
        do {
            try await file.saveState(next)
            snapshot = next
        } catch {
            operationError = error.localizedDescription
        }
    }
}

struct ArticleClient {
    let endpoint: URL
    let token: String
    let allowsInsecureLAN: Bool

    func prepare(url: URL, folder: String?) async throws -> (ImportPackage, [String: Data]) {
        guard CaptureRoute.acceptsService(endpoint, insecureLAN: allowsInsecureLAN) else {
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
