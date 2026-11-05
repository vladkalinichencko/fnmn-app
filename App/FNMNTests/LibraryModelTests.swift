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

        try await model.linkLibraryFolder(cloud) { _ in }
        XCTAssertEqual(model.cloudFolder?.standardizedFileURL, cloud.standardizedFileURL)

        let url = try XCTUnwrap(URL(string: "https://dl.acm.org/doi/3"))
        try await model.storeLink(url)
        XCTAssertEqual(model.snapshot.articles.count, 1)
        XCTAssertEqual(model.queries.unsortedItems.count, 1)
    }
}
