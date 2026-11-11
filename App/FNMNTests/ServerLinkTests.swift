import XCTest
@testable import FNMN

@MainActor
final class ServerLinkTests: XCTestCase {
    private final class StorageSpy: ServerConnectionStorage {
        var stored: ServerConnection?
        private(set) var loads = 0
        private(set) var saves = 0

        func load() -> ServerConnection? {
            loads += 1
            return stored
        }

        func save(_ connection: ServerConnection) throws {
            saves += 1
            stored = connection
        }
    }

    private func connection() throws -> ServerConnection {
        try ServerConnection(address: "https://mac.example.com", token: "secret")
    }

    func testInitDoesNotReadTheKeychain() {
        let storage = StorageSpy()
        _ = ServerLink(port: ServerClient(), storage: storage)
        XCTAssertEqual(storage.loads, 0)
    }

    func testTheSavedConnectionIsReadOnce() throws {
        let storage = StorageSpy()
        storage.stored = try connection()
        let link = ServerLink(port: ServerClient(), storage: storage)
        XCTAssertNotNil(link.savedConnection())
        XCTAssertTrue(link.hasReadConnection)
        XCTAssertNotNil(link.savedConnection())
        XCTAssertEqual(storage.loads, 1)
    }

    func testAnUnconfiguredServerIsReadOnceAndReportsMissing() {
        let storage = StorageSpy()
        let link = ServerLink(port: ServerClient(), storage: storage)
        XCTAssertNil(link.savedConnection())
        XCTAssertTrue(link.hasReadConnection)
        XCTAssertThrowsError(try link.configured()) { error in
            guard let error = error as? ServerConnectionError, case .notConfigured = error else {
                return XCTFail("Expected notConfigured, got \(error)")
            }
        }
        XCTAssertEqual(storage.loads, 1)
    }

    func testSaveMarksTheConnectionReadWithoutTouchingTheKeychain() throws {
        let storage = StorageSpy()
        let link = ServerLink(port: ServerClient(), storage: storage)
        let saved = try connection()
        try link.save(saved)
        XCTAssertTrue(link.hasReadConnection)
        XCTAssertEqual(storage.saves, 1)
        XCTAssertEqual(link.savedConnection()?.endpoint, saved.endpoint)
        XCTAssertEqual(link.savedConnection()?.token, saved.token)
        XCTAssertEqual(storage.loads, 0)
    }
}
