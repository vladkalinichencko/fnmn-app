import FNMNCore
import Foundation

@MainActor
protocol MacServicePort {
    func check(connection: MacConnection) async throws
    func startJob(url: URL, connection: MacConnection) async throws -> MacJob
    func job(_ id: String, connection: MacConnection) async throws -> MacJob
    /// Downloads the finished delivery archive to a temporary file.
    func delivery(of id: String, connection: MacConnection) async throws -> URL
    func startVideoDownload(url: URL, connection: MacConnection) async throws -> MacJob
    /// Downloads the finished video file to a temporary location.
    func videoFile(of id: String, connection: MacConnection) async throws -> URL
    /// Tells the Mac the result is stored, so it removes the file and forgets the job.
    func forget(_ id: String, connection: MacConnection) async throws
}

extension MacServicePort {
    /// Polls a job until it stops waiting. The pause grows from one to five seconds while the step
    /// stays the same and starts over when it changes.
    func finished(_ job: MacJob, connection: MacConnection, onStep: (ImportStep) -> Void) async throws -> MacJob {
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

struct MacJob: Decodable, Equatable {
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
        return ImportStep(text: text, fraction: fraction)
    }

    private var text: String {
        let count = total.map { " \(done ?? 0) of \($0)" } ?? ""
        switch phase == .queued ? "queued" : stage ?? "" {
        case "queued": return "Waiting for the Mac"
        case "fetchingPage": return "Fetching the page"
        case "fetchingAssets": return "Downloading files" + count
        case "waitingForOCR": return "Waiting for another PDF to finish"
        case "ocr": return "Reading page" + count
        case "assembly": return "Joining OCR with the PDF text"
        case "footnotes": return "Re-reading footnotes" + count
        case "formulas": return "Re-reading formulas" + count
        case "export": return "Checking the result"
        case "downloadingVideo": return "Downloading the video" + (total.map { " \(done ?? 0) of \($0) MB" } ?? "")
        case let other: return other
        }
    }
}

struct ImportStep: Equatable {
    let text: String
    let fraction: Double?
}

struct MacServiceClient: MacServicePort {
    func check(connection: MacConnection) async throws {
        var request = authorizedRequest(path: "health", connection: connection)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        try accept(response, data: data)
        let health = try JSONDecoder().decode(Health.self, from: data)
        guard health.status == "ok" else { throw URLError(.badServerResponse) }
    }

    func startJob(url: URL, connection: MacConnection) async throws -> MacJob {
        var request = authorizedRequest(path: "jobs", connection: connection)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JobRequest(url: url, folders: []))
        return try await decoded(MacJob.self, for: request)
    }

    func job(_ id: String, connection: MacConnection) async throws -> MacJob {
        try await decoded(MacJob.self, for: authorizedRequest(path: "jobs/\(id)", connection: connection))
    }

    func delivery(of id: String, connection: MacConnection) async throws -> URL {
        var request = authorizedRequest(path: "jobs/\(id)/package", connection: connection)
        request.timeoutInterval = 600
        let (file, response) = try await URLSession.shared.download(for: request)
        try accept(response, data: Data())
        return file
    }

    func forget(_ id: String, connection: MacConnection) async throws {
        var request = authorizedRequest(path: "jobs/\(id)", connection: connection)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        try accept(response, data: data)
    }

    func startVideoDownload(url: URL, connection: MacConnection) async throws -> MacJob {
        var request = authorizedRequest(path: "videos", connection: connection)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(VideoRequest(url: url))
        return try await decoded(MacJob.self, for: request)
    }

    func videoFile(of id: String, connection: MacConnection) async throws -> URL {
        var request = authorizedRequest(path: "jobs/\(id)/file", connection: connection)
        request.timeoutInterval = 600
        let (file, response) = try await URLSession.shared.download(for: request)
        try accept(response, data: Data())
        return file
    }

    private func decoded<Value: Decodable>(_ type: Value.Type, for request: URLRequest) async throws -> Value {
        let (data, response) = try await URLSession.shared.data(for: request)
        try accept(response, data: data)
        return try JSONDecoder().decode(type, from: data)
    }

    private func authorizedRequest(path: String, connection: MacConnection) -> URLRequest {
        var request = URLRequest(url: connection.endpoint.appending(path: path))
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func accept(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard 200 ..< 300 ~= http.statusCode else {
            let detail = (try? JSONDecoder().decode(FailureBody.self, from: data))?.detail
            throw MacServiceError.rejected(detail ?? "Mac service returned HTTP \(http.statusCode).")
        }
    }

    private struct Health: Decodable { let status: String }
    private struct JobRequest: Encodable { let url: URL; let folders: [String] }
    private struct VideoRequest: Encodable { let url: URL }
    private struct FailureBody: Decodable { let detail: String }
}

enum MacServiceError: Error, LocalizedError {
    case rejected(String)

    var errorDescription: String? {
        guard case let .rejected(message) = self else { return nil }
        return message
    }
}
