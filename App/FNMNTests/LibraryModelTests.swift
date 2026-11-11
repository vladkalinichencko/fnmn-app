import FNMNCore
import XCTest
@testable import FNMN

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

    func testAReindexGivesAnOldMaterialItsSearchBodyBack() async throws {
        UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        let (model, root) = makeModel()
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        }
        let cloud = root.appending(path: "FNMN")
        let deliveries = cloud.appending(path: "deliveries")
        try FileManager.default.createDirectory(at: deliveries, withIntermediateDirectories: true)
        let package = ImportPackage(
            material: Material(id: "article:reindex", kind: .article, title: "Old Timer", sourceURL: URL(string: "https://example.com/old")!),
            sections: [],
            blocks: [],
            body: "A paragraph about a waffle iron."
        )
        try writeDelivery(package, to: deliveries.appending(path: "old.tar"))

        await model.load()
        try await model.linkLibraryFolder(cloud) { _ in }
        let itemID = package.material.id
        let found = await model.search("waffle")
        XCTAssertEqual(found.first?.source, .text)

        await LibraryFile(url: model.storageURL).removeSearchBody(itemID)
        let gone = await model.search("waffle")
        XCTAssertTrue(gone.isEmpty)

        await model.reindexSearch()
        let hits = await model.search("waffle")
        XCTAssertEqual(hits.first?.source, .text)
        XCTAssertEqual(hits.first?.itemID, itemID)
    }

    private func writeDelivery(_ package: ImportPackage, to url: URL) throws {
        var archive = Data()
        func add(_ name: String, _ data: Data) {
            var header = [UInt8](repeating: 0, count: 512)
            func put(_ text: String, at offset: Int) {
                for (index, byte) in text.utf8.enumerated() {
                    header[offset + index] = byte
                }
            }
            put(name, at: 0)
            put("0000644", at: 100)
            put("0000000", at: 108)
            put("0000000", at: 116)
            put(String(format: "%011o", data.count), at: 124)
            put("00000000000", at: 136)
            put("        ", at: 148)
            put("0", at: 156)
            put("ustar", at: 257)
            put("00", at: 263)
            put(String(format: "%06o", header.reduce(0) { $0 + Int($1) }), at: 148)
            archive.append(contentsOf: header)
            archive.append(data)
            archive.append(Data(count: (512 - data.count % 512) % 512))
        }
        add("package.json", try JSONEncoder().encode(package))
        archive.append(Data(count: 1024))
        try archive.write(to: url)
    }

    func testDeletingAMaterialTakesItsDeliveryOutOfTheFolder() async throws {        UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
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
