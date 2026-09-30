import FNMNCore
import Foundation

@MainActor
protocol ServerPort {
    func check(connection: ServerConnection) async throws
    func startJob(url: URL, connection: ServerConnection) async throws -> ServerJob
    /// Sends a file for the server to make a material of by its type.
    func startFileJob(file: URL, connection: ServerConnection) async throws -> ServerJob
    func job(_ id: String, connection: ServerConnection) async throws -> ServerJob
    /// Downloads the finished delivery archive to a temporary file.
    func delivery(of id: String, connection: ServerConnection) async throws -> URL
    func startVideoDownload(url: URL, connection: ServerConnection) async throws -> ServerJob
    /// Downloads the finished video file to a temporary location.
    func videoFile(of id: String, connection: ServerConnection) async throws -> URL
    /// Tells the server to remove the job and its file.
    func forget(_ id: String, connection: ServerConnection) async throws
}

extension ServerPort {
    /// Polls a job until it stops waiting. The pause grows from one to five seconds while the step
    /// stays the same and starts over when it changes.
    func finished(_ job: ServerJob, connection: ServerConnection, onStep: (ImportStep) -> Void) async throws -> ServerJob {
        var job = job
        var pause = 1
        while job.isWaiting {
            onStep(job.step)
            try await Task.sleep(for: .seconds(pause))
            let next = try await self.job(job.id, connection: connection)
            pause = next.step == job.step ? min(pause + 1, 5) : 1
            job = next
        }
        return job
    }
}

struct ServerJob: Decodable, Equatable {
    enum Phase: String, Decodable { case queued, running, done, failed }

    let id: String
    let phase: Phase
    let stage: String?
    let done: Int?
    let total: Int?
    let error: String?

    var isWaiting: Bool { phase == .queued || phase == .running }

    var step: ImportStep {
        let fraction = total.flatMap { total in done.map { total > 0 ? Double($0) / Double(total) : 0 } }
        let (text, symbol) = described
        return ImportStep(text: text, fraction: fraction, symbol: symbol)
    }

    private var described: (text: String, symbol: String) {
        let count = total.map { " \(done ?? 0) of \($0)" } ?? ""
        switch phase == .queued ? "queued" : stage ?? "" {
        case "queued": return ("Waiting for the server", "clock")
        case "fetchingPage": return ("Fetching the page", "globe")
        case "fetchingAssets": return ("Downloading files" + count, "arrow.down.circle")
        case "waitingForOCR": return ("Waiting for another PDF to finish", "clock")
        case "ocr": return ("Reading page" + count, "doc.text.viewfinder")
        case "assembly": return ("Joining OCR with the PDF text", "doc.on.doc")
        case "footnotes": return ("Re-reading footnotes" + count, "doc.text.viewfinder")
        case "formulas": return ("Re-reading formulas" + count, "function")
        case "export": return ("Checking the result", "checkmark.seal")
        case "downloadingVideo": return ("Downloading the video" + (total.map { " \(done ?? 0) of \($0) MB" } ?? ""), "arrow.down.circle")
        case let other: return (other, "gearshape")
        }
    }
}

/// Where a job is: a caption, how far along when that is known, and the symbol a card shows for the stage.
struct ImportStep: Equatable {
    let text: String
    let fraction: Double?
    let symbol: String
}

struct ServerClient: ServerPort {
    func check(connection: ServerConnection) async throws {
        var request = authorizedRequest(path: "health", connection: connection)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        try accept(response, data: data)
        let health = try JSONDecoder().decode(Health.self, from: data)
        guard health.status == "ok" else { throw URLError(.badServerResponse) }
    }

    func startJob(url: URL, connection: ServerConnection) async throws -> ServerJob {
        var request = authorizedRequest(path: "jobs", connection: connection)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JobRequest(url: url, folders: []))
        return try await decoded(ServerJob.self, for: request)
    }

    func startFileJob(file: URL, connection: ServerConnection) async throws -> ServerJob {
        var request = authorizedRequest(path: "files", connection: connection)
        request.url?.append(queryItems: [URLQueryItem(name: "name", value: file.lastPathComponent)])
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: file)
        try accept(response, data: data)
        return try JSONDecoder().decode(ServerJob.self, from: data)
    }

    func job(_ id: String, connection: ServerConnection) async throws -> ServerJob {
        try await decoded(ServerJob.self, for: authorizedRequest(path: "jobs/\(id)", connection: connection))
    }

    func delivery(of id: String, connection: ServerConnection) async throws -> URL {
        var request = authorizedRequest(path: "jobs/\(id)/package", connection: connection)
        request.timeoutInterval = 600
        let (file, response) = try await URLSession.shared.download(for: request)
        try accept(response, data: Data())
        return file
    }

    func forget(_ id: String, connection: ServerConnection) async throws {
        var request = authorizedRequest(path: "jobs/\(id)", connection: connection)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        try accept(response, data: data)
    }

    func startVideoDownload(url: URL, connection: ServerConnection) async throws -> ServerJob {
        var request = authorizedRequest(path: "videos", connection: connection)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(VideoRequest(url: url))
        return try await decoded(ServerJob.self, for: request)
    }

    func videoFile(of id: String, connection: ServerConnection) async throws -> URL {
        var request = authorizedRequest(path: "jobs/\(id)/file", connection: connection)
        request.timeoutInterval = 600
        let (download, response) = try await URLSession.shared.download(for: request)
        try accept(response, data: Data())
        // The download lands as a `.tmp`; the file keeps the extension the server gave it, which names the original.
        let name = response.suggestedFilename.map { URL(filePath: $0).pathExtension } ?? ""
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            .appendingPathExtension(name.isEmpty ? "mp4" : name)
        try FileManager.default.moveItem(at: download, to: file)
        return file
    }

    private func decoded<Value: Decodable>(_ type: Value.Type, for request: URLRequest) async throws -> Value {
        let (data, response) = try await URLSession.shared.data(for: request)
        try accept(response, data: data)
        return try JSONDecoder().decode(type, from: data)
    }

    private func authorizedRequest(path: String, connection: ServerConnection) -> URLRequest {
        var request = URLRequest(url: connection.endpoint.appending(path: path))
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func accept(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard 200 ..< 300 ~= http.statusCode else {
            let detail = (try? JSONDecoder().decode(FailureBody.self, from: data))?.detail
            throw ServerError.rejected(detail ?? "The server returned HTTP \(http.statusCode).")
        }
    }

    private struct Health: Decodable { let status: String }
    private struct JobRequest: Encodable { let url: URL; let folders: [String] }
    private struct VideoRequest: Encodable { let url: URL }
    private struct FailureBody: Decodable { let detail: String }
}

enum ServerError: Error, LocalizedError {
    case rejected(String)

    var errorDescription: String? {
        guard case let .rejected(message) = self else { return nil }
        return message
    }
}
