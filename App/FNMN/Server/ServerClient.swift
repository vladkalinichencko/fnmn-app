import FNMNCore
import Foundation

@MainActor
protocol ServerPort {
    func check(connection: ServerConnection) async throws
    func startJob(url: URL, connection: ServerConnection) async throws -> ServerJob
    /// Sends a file for the server to make a material of by its type, reporting how much of it is sent.
    func startFileJob(file: URL, connection: ServerConnection, onStep: @escaping @MainActor (ImportStep) -> Void) async throws -> ServerJob
    func job(_ id: String, connection: ServerConnection) async throws -> ServerJob
    /// Downloads the finished delivery archive to a temporary file, reporting how much of it has arrived.
    func delivery(of id: String, connection: ServerConnection, onStep: @escaping @MainActor (ImportStep) -> Void) async throws -> URL
    func startVideoDownload(url: URL, connection: ServerConnection) async throws -> ServerJob
    /// Downloads the finished video file to a temporary location, reporting how much of it has arrived.
    func videoFile(of id: String, connection: ServerConnection, onStep: @escaping @MainActor (ImportStep) -> Void) async throws -> URL
    /// Tells the server to remove the job and its file.
    func forget(_ id: String, connection: ServerConnection) async throws
    /// Re-fetches one digest post's pictures on the Mac; the entries name files the phone can download.
    func refreshDigestPost(_ postID: String, connection: ServerConnection) async throws -> [DigestPackage.Post.Media]
    /// One picture of a refreshed digest post, by the file name the Mac returned.
    func digestMedia(_ name: String, connection: ServerConnection) async throws -> Data
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

    func startFileJob(file: URL, connection: ServerConnection, onStep: @escaping @MainActor (ImportStep) -> Void) async throws -> ServerJob {
        var request = authorizedRequest(path: "files", connection: connection)
        request.url?.append(queryItems: [URLQueryItem(name: "name", value: file.lastPathComponent)])
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: file, delegate: Transfer(.sending, onStep: onStep))
        try accept(response, data: data)
        return try JSONDecoder().decode(ServerJob.self, from: data)
    }

    func job(_ id: String, connection: ServerConnection) async throws -> ServerJob {
        try await repeatingDrops { try await decoded(ServerJob.self, for: authorizedRequest(path: "jobs/\(id)", connection: connection)) }
    }

    func delivery(of id: String, connection: ServerConnection, onStep: @escaping @MainActor (ImportStep) -> Void) async throws -> URL {
        var request = authorizedRequest(path: "jobs/\(id)/package", connection: connection)
        request.timeoutInterval = 600
        let (file, response) = try await repeatingDrops {
            try await URLSession.shared.download(for: request, delegate: Transfer(.receiving, onStep: onStep))
        }
        try accept(response, data: Data())
        return file
    }

    func forget(_ id: String, connection: ServerConnection) async throws {
        var request = authorizedRequest(path: "jobs/\(id)", connection: connection)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        try accept(response, data: data)
    }

    func refreshDigestPost(_ postID: String, connection: ServerConnection) async throws -> [DigestPackage.Post.Media] {
        var request = authorizedRequest(path: "digest/refresh", connection: connection)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DigestRefreshRequest(postID: postID))
        request.timeoutInterval = 300
        let (data, response) = try await URLSession.shared.data(for: request)
        try accept(response, data: data)
        return try JSONDecoder().decode(DigestMediaResponse.self, from: data).media
    }

    func digestMedia(_ name: String, connection: ServerConnection) async throws -> Data {
        var request = authorizedRequest(path: "digest/media/\(name)", connection: connection)
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        try accept(response, data: data)
        return data
    }

    func startVideoDownload(url: URL, connection: ServerConnection) async throws -> ServerJob {
        var request = authorizedRequest(path: "videos", connection: connection)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(VideoRequest(url: url))
        return try await decoded(ServerJob.self, for: request)
    }

    func videoFile(of id: String, connection: ServerConnection, onStep: @escaping @MainActor (ImportStep) -> Void) async throws -> URL {
        var request = authorizedRequest(path: "jobs/\(id)/file", connection: connection)
        request.timeoutInterval = 600
        let (download, response) = try await repeatingDrops {
            try await URLSession.shared.download(for: request, delegate: Transfer(.receiving, onStep: onStep))
        }
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

    /// Repeats a request the network dropped on the way, which a phone behind a VPN and Funnel sees now and then.
    /// The server keeps a job and its file until the phone forgets them, so a repeat gets the same answer.
    private func repeatingDrops<Value>(_ request: () async throws -> Value) async throws -> Value {
        let dropped: Set<URLError.Code> = [.networkConnectionLost, .timedOut, .cannotConnectToHost, .notConnectedToInternet]
        for pause in [2, 5] {
            do {
                return try await request()
            } catch let error as URLError where dropped.contains(error.code) {
                try await Task.sleep(for: .seconds(pause))
            }
        }
        return try await request()
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
    private struct DigestRefreshRequest: Encodable {
        let postID: String

        enum CodingKeys: String, CodingKey {
            case postID = "post_id"
        }
    }
    private struct DigestMediaResponse: Decodable { let media: [DigestPackage.Post.Media] }
    private struct FailureBody: Decodable { let detail: String }
}

/// How far a file sent to the server or downloaded from it has got, as an import step once per whole percent.
/// URLSession counts the bytes on its own thread; the steps go to the main thread in the order they were counted,
/// so the last one arrives before the code awaiting the transfer goes on.
private final class Transfer: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    enum Direction { case sending, receiving }

    private let direction: Direction
    private let onStep: @MainActor (ImportStep) -> Void
    private var observation: NSKeyValueObservation?
    /// Read and written only on the main thread.
    private var percent = -1

    init(_ direction: Direction, onStep: @escaping @MainActor (ImportStep) -> Void) {
        self.direction = direction
        self.onStep = onStep
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = switch direction {
        case .sending: task.observe(\.countOfBytesSent) { [weak self] task, _ in self?.moved(task.countOfBytesSent, of: task.countOfBytesExpectedToSend) }
        case .receiving: task.observe(\.countOfBytesReceived) { [weak self] task, _ in self?.moved(task.countOfBytesReceived, of: task.countOfBytesExpectedToReceive) }
        }
    }

    private func moved(_ done: Int64, of total: Int64) {
        guard total > 0 else { return }
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                let now = Int(done * 100 / total)
                guard now != percent else { return }
                percent = now
                onStep(step(done, of: total))
            }
        }
    }

    private func step(_ done: Int64, of total: Int64) -> ImportStep {
        let count = "\(done.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))"
        return switch direction {
        case .sending: ImportStep(text: "Sending to the server \(count)", fraction: Double(done) / Double(total), symbol: "arrow.up.circle")
        case .receiving: ImportStep(text: "Downloading \(count)", fraction: Double(done) / Double(total), symbol: "arrow.down.circle")
        }
    }
}

enum ServerError: Error, LocalizedError {
    case rejected(String)

    var errorDescription: String? {
        guard case let .rejected(message) = self else { return nil }
        return message
    }
}
