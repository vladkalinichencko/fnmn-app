import Foundation
import Observation

/// The only way into the server: its saved address and token, and the port every request goes through.
@MainActor @Observable
final class ServerLink {
    private(set) var connection: ServerConnection?
    /// Whether the saved connection has been read; a view shows its loading state until it is true.
    private(set) var hasReadConnection = false
    let port: any ServerPort
    private let storage: any ServerConnectionStorage

    init(port: any ServerPort = ServerClient(), storage: any ServerConnectionStorage = KeychainServerConnectionStore()) {
        self.port = port
        self.storage = storage
    }

    /// The saved connection, read from the Keychain the first time something asks for it. Reading it in `init`
    /// runs inside `FNMNApp.init`, and the synchronous Keychain call delays the first frame.
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
