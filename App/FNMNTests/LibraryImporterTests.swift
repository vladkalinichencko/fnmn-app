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

        var published = LibrarySnapshot()
        let write: LibraryImporter.Write = { _, next in
            published = try await next(published)
        }
        let importer = LibraryImporter(file: fixture.file)
        try await importer.storeLink(try link("https://dl.acm.org/doi/1"), write: write)

        XCTAssertEqual(published.articles.count, 1)
        XCTAssertNotNil(published.articles.first?.delivery)
        let reloaded = try await fixture.file.load().catalog
        XCTAssertEqual(reloaded.articles.count, 1)
    }

    func testAnotherDeviceReadsTheDeliveryFromTheFolder() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var written = LibrarySnapshot()
        let write: LibraryImporter.Write = { _, next in
            written = try await next(written)
        }
        let first = LibraryImporter(file: fixture.file)
        try await first.storeLink(try link("https://dl.acm.org/doi/2"), write: write)
        XCTAssertEqual(written.articles.count, 1)

        var read = LibrarySnapshot()
        let readWrite: LibraryImporter.Write = { _, next in
            read = try await next(read)
        }
        let other = LibraryFile(url: fixture.root.appending(path: "other"), cache: fixture.root.appending(path: "cache"))
        await other.useCloudFolder(fixture.cloud)
        let second = LibraryImporter(file: other)
        try await second.readChangedDeliveries(in: fixture.cloud, write: readWrite)
        XCTAssertEqual(read.articles.count, 1)
    }

    func testAKeptFileIsKnownByItsBytes() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let picked = fixture.root.appending(path: "note.md")
        try Data("# Title\n\nA paragraph.".utf8).write(to: picked)
        var published = LibrarySnapshot()
        let write: LibraryImporter.Write = { _, next in
            published = try await next(published)
        }
        let importer = LibraryImporter(file: fixture.file)
        let materialID = try await importer.storeFile(picked, write: write)
        XCTAssertEqual(published.articles.count, 1)
        XCTAssertEqual(published.articles.first?.material.id, materialID)
    }
}
