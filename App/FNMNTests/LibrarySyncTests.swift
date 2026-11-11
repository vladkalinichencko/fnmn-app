import CryptoKit
import FNMNCore
import XCTest
@testable import FNMN

@MainActor
final class LibrarySyncTests: XCTestCase {
    func testTheMachineWalksFlushJournalsCatalogDeliveries() {
        var state = librarySyncReduce(.idle, .begin)
        XCTAssertEqual(state, .syncing(step: .flush, pending: 0))
        state = librarySyncReduce(state, .stageSucceeded(pending: 0))
        XCTAssertEqual(state, .syncing(step: .journals, pending: 0))
        state = librarySyncReduce(state, .stageSucceeded(pending: 2))
        XCTAssertEqual(state, .syncing(step: .catalog, pending: 2))
        state = librarySyncReduce(state, .stageSucceeded(pending: 0))
        XCTAssertEqual(state, .syncing(step: .deliveries, pending: 2))
        state = librarySyncReduce(state, .stageSucceeded(pending: 3))
        XCTAssertEqual(state, .finished(pending: 5))
    }

    func testAStageFailureStopsTheRunAndBeginStartsItAgain() {
        let failed = librarySyncReduce(.syncing(step: .journals, pending: 1), .failed("boom"))
        XCTAssertEqual(failed, .failed("boom"))
        XCTAssertEqual(librarySyncReduce(failed, .begin), .syncing(step: .flush, pending: 0))
        XCTAssertEqual(librarySyncReduce(.finished(pending: 4), .begin), .syncing(step: .flush, pending: 0))
    }

    func testEventsInTheWrongStateChangeNothing() {
        XCTAssertEqual(librarySyncReduce(.idle, .stageSucceeded(pending: 1)), .idle)
        XCTAssertEqual(librarySyncReduce(.finished(pending: 2), .stageSucceeded(pending: 1)), .finished(pending: 2))
        XCTAssertEqual(librarySyncReduce(.failed("x"), .stageSucceeded(pending: 1)), .failed("x"))
    }

    private struct Pair {
        let phone: LibraryModel
        let pad: LibraryModel
        let cloud: URL
        let root: URL
    }

    private func makePair() async throws -> Pair {
        let root = FileManager.default.temporaryDirectory.appending(path: "sync-\(UUID().uuidString)")
        let cloud = root.appending(path: "FNMN")
        try FileManager.default.createDirectory(at: cloud.appending(path: "deliveries"), withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        UserDefaults.standard.set("phone", forKey: "deviceID")
        let phone = LibraryModel(storageURL: root.appending(path: "phone-app"), cacheURL: root.appending(path: "phone-cache"))
        UserDefaults.standard.set("pad", forKey: "deviceID")
        let pad = LibraryModel(storageURL: root.appending(path: "pad-app"), cacheURL: root.appending(path: "pad-cache"))
        await phone.load()
        await pad.load()
        try await phone.linkLibraryFolder(cloud) { _ in }
        try await pad.linkLibraryFolder(cloud) { _ in }
        return Pair(phone: phone, pad: pad, cloud: cloud, root: root)
    }

    private func assertSameLibrary(_ first: LibraryModel, _ second: LibraryModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(first.snapshot.albums, second.snapshot.albums, file: file, line: line)
        XCTAssertEqual(first.snapshot.placements, second.snapshot.placements, file: file, line: line)
        XCTAssertEqual(first.snapshot.archived, second.snapshot.archived, file: file, line: line)
        XCTAssertEqual(first.snapshot.deletedAt, second.snapshot.deletedAt, file: file, line: line)
        XCTAssertEqual(Set(first.snapshot.articles.map(\.material.id)), Set(second.snapshot.articles.map(\.material.id)), file: file, line: line)
    }

    func testTwoDevicesReachTheSameLibrary() async throws {
        let pair = try await makePair()
        defer {
            try? FileManager.default.removeItem(at: pair.root)
            UserDefaults.standard.removeObject(forKey: "deviceID")
            UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        }

        let url = try XCTUnwrap(URL(string: "https://example.com/shared-story"))
        try await pair.phone.storeLink(url)
        let itemID = try XCTUnwrap(pair.phone.snapshot.articles.first?.material.id)
        await pair.phone.apply(.addToCollection("Reading", itemIDs: [itemID]))
        await pair.phone.saveProgress()

        await pair.pad.syncWithOtherDevices()
        assertSameLibrary(pair.phone, pair.pad)
        XCTAssertEqual(pair.pad.snapshot.albums(of: itemID), ["Reading"])

        await pair.pad.apply(.removeFromCollection("Reading", itemID: itemID))
        await pair.pad.saveProgress()
        await pair.phone.syncWithOtherDevices()
        assertSameLibrary(pair.phone, pair.pad)
        XCTAssertTrue(pair.phone.queries.unsortedItems.contains { $0.id == itemID })
        XCTAssertTrue(pair.pad.queries.unsortedItems.contains { $0.id == itemID })
    }

    func testAPlacementWaitsForItsDeliveryAndTheDeliveryKeepsIt() async throws {
        let pair = try await makePair()
        defer {
            try? FileManager.default.removeItem(at: pair.root)
            UserDefaults.standard.removeObject(forKey: "deviceID")
            UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        }

        let ghostID = "article:ghost"
        let writer = LibraryFile(url: pair.root.appending(path: "writer-app"), cache: pair.root.appending(path: "writer-cache"))
        await writer.useCloudFolder(pair.cloud)
        try await writer.appendJournal(
            [JournalEvent(time: .now, change: .library(.addToCollection("Rendering", itemIDs: [ghostID])))],
            device: "server"
        )

        await pair.pad.syncWithOtherDevices()
        XCTAssertNil(pair.pad.snapshot.articles.first { $0.material.id == ghostID })
        XCTAssertEqual(pair.pad.snapshot.placements[ghostID], ["Rendering"])

        let package = ImportPackage(
            material: Material(id: ghostID, kind: .article, title: "Ghost", sourceURL: URL(string: "https://example.com/ghost")!),
            sections: [],
            blocks: [],
            folders: ["Suggested"],
            body: "A body long enough to be a document."
        )
        let name = SHA256.hash(data: Data(ghostID.utf8)).map { String(format: "%02x", $0) }.joined() + ".tar"
        try writeDelivery(package, to: pair.cloud.appending(path: "deliveries").appending(path: name))

        await pair.pad.syncWithOtherDevices()
        XCTAssertEqual(pair.pad.snapshot.albums(of: ghostID), ["Rendering"])
        XCTAssertFalse(pair.pad.snapshot.albums(of: ghostID).contains("Suggested"))
    }

    func testTheCatalogRefreshesOnSync() async throws {
        let pair = try await makePair()
        defer {
            try? FileManager.default.removeItem(at: pair.root)
            UserDefaults.standard.removeObject(forKey: "deviceID")
            UserDefaults.standard.removeObject(forKey: "cloudFolderBookmark")
        }

        let catalog = #"{"collections":[{"id":"c1","name":"Theory"}],"sources":[]}"#
        try Data(catalog.utf8).write(to: pair.cloud.appending(path: "catalog.json"))
        await pair.pad.syncWithOtherDevices()
        XCTAssertEqual(pair.pad.snapshot.browserCatalog?.collections.map(\.name), ["Theory"])

        let changed = #"{"collections":[{"id":"c1","name":"Theory"},{"id":"c2","name":"Design"}],"sources":[]}"#
        try Data(changed.utf8).write(to: pair.cloud.appending(path: "catalog.json"))
        await pair.pad.syncWithOtherDevices()
        XCTAssertEqual(pair.pad.snapshot.browserCatalog?.collections.map(\.name), ["Theory", "Design"])
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
}
