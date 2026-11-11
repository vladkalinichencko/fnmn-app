import Foundation
import Observation

@MainActor @Observable
final class ServerLink {
    private(set) var connection: ServerConnection?
    private(set) var hasReadConnection = false
    let port: any ServerPort
    private let storage: any ServerConnectionStorage

    init(port: any ServerPort = ServerClient(), storage: any ServerConnectionStorage = KeychainServerConnectionStore()) {
        self.port = port
        self.storage = storage
    }

    func savedConnection() -> ServerConnection? {
        if !hasReadConnection {
            hasReadConnection = true
            connection = storage.load()
        }
        return connection
    }

    func save(_ connection: ServerConnection) throws {
        try storage.save(connection)
        self.connection = connection
        hasReadConnection = true
    }

    func check() async throws {
        try await port.check(connection: try configured())
    }

    func configured() throws -> ServerConnection {
        guard let connection = savedConnection() else {
            throw ServerConnectionError.notConfigured
        }
        return connection
    }
}
