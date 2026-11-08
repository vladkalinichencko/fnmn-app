import FNMNCore
import XCTest
@testable import FNMN

/// Links, files and deliveries come in through one stateless importer and land in the catalog.
@MainActor
final class LibraryImporterTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let cloud: URL
        let file: LibraryFile
    }

    /// What the model's serialized write publishes, for a test that reads the catalog after a call.
    private final class Published {
        var snapshot = LibrarySnapshot()
        var write: LibraryImporter.Write {
            { [self] _, next in snapshot = try await next(snapshot) }
        }
    }

    private func makeFixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: "import-\(UUID().uuidString)")
        let cloud = root.appending(path: "FNMN")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        let file = LibraryFile(url: root.appending(path: "app"), cache: root.appending(path: "cache"))
        await file.useCloudFolder(cloud)
        return Fixture(root: root, cloud: cloud, file: file)
    }

    private func link(_ value: String) throws -> URL {
        try XCTUnwrap(URL(string: value))
    }

    func testALinkKeptAsItIsBecomesADelivery() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let published = Published()
        let importer = LibraryImporter(file: fixture.file)
        try await importer.storeLink(try link("https://dl.acm.org/doi/1"), write: published.write)

        XCTAssertEqual(published.snapshot.articles.count, 1)
        XCTAssertNotNil(published.snapshot.articles.first?.delivery)
        let reloaded = try await fixture.file.load().catalog
        XCTAssertEqual(reloaded.articles.count, 1)
    }

    func testAnotherDeviceReadsTheDeliveryFromTheFolder() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let written = Published()
        let first = LibraryImporter(file: fixture.file)
        try await first.storeLink(try link("https://dl.acm.org/doi/2"), write: written.write)
        XCTAssertEqual(written.snapshot.articles.count, 1)

        let read = Published()
        let other = LibraryFile(url: fixture.root.appending(path: "other"), cache: fixture.root.appending(path: "cache"))
        await other.useCloudFolder(fixture.cloud)
        let second = LibraryImporter(file: other)
        try await second.readChangedDeliveries(in: fixture.cloud, write: read.write)
        XCTAssertEqual(read.snapshot.articles.count, 1)
    }

    func testAKeptFileIsKnownByItsBytes() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let picked = fixture.root.appending(path: "note.md")
        try Data("# Title\n\nA paragraph.".utf8).write(to: picked)
        let published = Published()
        let importer = LibraryImporter(file: fixture.file)
        let materialID = try await importer.storeFile(picked, write: published.write)
        XCTAssertEqual(published.snapshot.articles.count, 1)
        XCTAssertEqual(published.snapshot.articles.first?.material.id, materialID)
    }

    func testEveryUnreadableDeliveryIsNamed() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let deliveries = fixture.cloud.appending(path: "deliveries")
        try FileManager.default.createDirectory(at: deliveries, withIntermediateDirectories: true)
        try Data("not a tar".utf8).write(to: deliveries.appending(path: "a.tar"))
        try Data("still not a tar".utf8).write(to: deliveries.appending(path: "b.tar"))
        let published = Published()
        do {
            try await LibraryImporter(file: fixture.file).readChangedDeliveries(in: fixture.cloud, write: published.write)
            XCTFail("two unreadable deliveries must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("a.tar"))
            XCTAssertTrue(error.localizedDescription.contains("b.tar"))
        }
    }
}
