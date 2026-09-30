import Foundation
import Observation

/// The only way into the server: its saved address and token, and the port every request goes through.
@MainActor @Observable
final class ServerLink {
    private(set) var connection: ServerConnection?
    let port: any ServerPort
    private let storage: any ServerConnectionStorage

    init(port: any ServerPort = ServerClient(), storage: any ServerConnectionStorage = KeychainServerConnectionStore()) {
        self.port = port
        self.storage = storage
        connection = storage.load()
    }

    func save(_ connection: ServerConnection) throws {
        try storage.save(connection)
        self.connection = connection
    }

    func check() async throws {
        try await port.check(connection: try configured())
    }

    func configured() throws -> ServerConnection {
        guard let connection else { throw ServerConnectionError.notConfigured }
        return connection
    }
}
