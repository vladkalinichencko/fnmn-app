import Foundation
import Observation

/// The only way into the Mac: its saved address and token, and the service port every request goes through.
@MainActor @Observable
final class MacLink {
    private(set) var connection: MacConnection?
    let port: any MacServicePort
    private let storage: any MacConnectionStorage

    init(port: any MacServicePort = MacServiceClient(), storage: any MacConnectionStorage = KeychainMacConnectionStore()) {
        self.port = port
        self.storage = storage
        connection = storage.load()
    }

    func save(_ connection: MacConnection) throws {
        try storage.save(connection)
        self.connection = connection
    }

    func check() async throws {
        try await port.check(connection: try configured())
    }

    func configured() throws -> MacConnection {
        guard let connection else { throw MacConnectionError.notConfigured }
        return connection
    }
}
