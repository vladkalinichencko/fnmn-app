import Foundation

@MainActor
protocol MacServicePort {
    func check(connection: MacConnection) async throws
    func prepare(url: URL, connection: MacConnection) async throws -> (ImportPackage, [String: Data])
}

struct ArticleClient: MacServicePort {
    func check(connection: MacConnection) async throws {
        var request = authorizedRequest(path: "health", connection: connection)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        try accept(response, data: data)
        let health = try JSONDecoder().decode(Health.self, from: data)
        guard health.status == "ok" else { throw URLError(.badServerResponse) }
    }

    func prepare(url: URL, connection: MacConnection) async throws -> (ImportPackage, [String: Data]) {
        var request = authorizedRequest(path: "articles", connection: connection)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ArticleRequest(url: url, folders: []))
        let (data, response) = try await URLSession.shared.data(for: request)
        try accept(response, data: data)
        let delivery = try JSONDecoder().decode(ArticleDelivery.self, from: data)
        return (delivery.package, delivery.files)
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
            throw ArticleServiceError.rejected(detail ?? "Mac service returned HTTP \(http.statusCode).")
        }
    }

    private struct Health: Decodable { let status: String }
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
