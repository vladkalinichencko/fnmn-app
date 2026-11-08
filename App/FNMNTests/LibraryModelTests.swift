import FNMNCore
import XCTest
@testable import FNMN

/// The model sequences the store: loading, the linked folder, and an import landing in the catalog.
@MainActor
final class LibraryModelTests: XCTestCase {
    private func makeModel() -> (model: LibraryModel, root: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "model-\(UUID().uuidString)")
        let model = LibraryModel(storageURL: root.appending(path: "app"), cacheURL: root.appending(path: "cache"))
        return (model, root)
    }

    func testAnEmptyLibraryLoadsReadyWithoutAFolder() async {
        UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        let (model, root) = makeModel()
        defer { try? FileManager.default.removeItem(at: root) }

        await model.load()
        XCTAssertEqual(model.loadState, .ready)
        XCTAssertEqual(model.phase, .needsFolder)
        XCTAssertNil(model.cloudFolder)
        XCTAssertTrue(model.queries.unsortedItems.isEmpty)
    }

    func testALinkedFolderAndAKeptLinkShowUpInTheCatalog() async throws {
        UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        let (model, root) = makeModel()
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        }
        let cloud = root.appending(path: "FNMN")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)

        await model.load()
        try await model.linkLibraryFolder(cloud) { _ in }
        XCTAssertEqual(model.cloudFolder?.standardizedFileURL, cloud.standardizedFileURL)
        XCTAssertEqual(model.phase, .ready)

        let url = try XCTUnwrap(URL(string: "https://dl.acm.org/doi/3"))
        try await model.storeLink(url)
        XCTAssertEqual(model.snapshot.articles.count, 1)
        XCTAssertEqual(model.queries.unsortedItems.count, 1)
    }

    func testSearchFindsAMaterialByItsAddressAndANoteByItsWords() async throws {
        UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        let (model, root) = makeModel()
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        }
        let cloud = root.appending(path: "FNMN")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        await model.load()
        try await model.linkLibraryFolder(cloud) { _ in }
        let url = try XCTUnwrap(URL(string: "https://example.com/quantum-widgets"))
        try await model.storeLink(url)
        let itemID = try XCTUnwrap(model.snapshot.articles.first?.material.id)
        await model.apply(.note("a thought about entropy", AnnotationTarget(materialID: itemID, piece: 3, text: "Some text here.")))

        let byTitle = await model.search("quantum")
        XCTAssertEqual(byTitle.map(\.source), [.material])
        XCTAssertEqual(byTitle.first?.itemID, itemID)

        let byNote = await model.search("entropy")
        XCTAssertEqual(byNote.map(\.source), [.annotation])
        XCTAssertEqual(byNote.first?.piece, 3)
        XCTAssertTrue(byNote.first?.text.contains("entropy") == true)
        XCTAssertEqual(byNote.first?.span.map { (("a thought about entropy" as NSString).substring(with: NSRange(location: $0.start, length: $0.length))) }, "entropy")

        let nothing = await model.search("nothing of the kind")
        XCTAssertTrue(nothing.isEmpty)
    }

    func testDeletingAMaterialTakesItsDeliveryOutOfTheFolder() async throws {
        UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        let (model, root) = makeModel()
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        }
        let cloud = root.appending(path: "FNMN")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        try await model.linkLibraryFolder(cloud) { _ in }
        let url = try XCTUnwrap(URL(string: "https://dl.acm.org/doi/4"))
        try await model.storeLink(url)
        let entry = try XCTUnwrap(model.snapshot.articles.first)
        let deliveries = cloud.appending(path: "deliveries")
        let before = try FileManager.default.contentsOfDirectory(atPath: deliveries.path)
        XCTAssertEqual(before.count, 1)

        await model.apply(.delete(itemID: entry.material.id))

        XCTAssertTrue(model.snapshot.articles.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: deliveries.path).isEmpty)
    }
}
