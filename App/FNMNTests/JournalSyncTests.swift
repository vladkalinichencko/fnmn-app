import FNMNCore
import XCTest
@testable import FNMN

@MainActor
final class JournalSyncTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let cloud: URL
        let file: LibraryFile
    }

    private func makeFixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString)")
        let cloud = root.appending(path: "FNMN")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        let file = LibraryFile(url: root.appending(path: "app"), cache: root.appending(path: "cache"))
        await file.useCloudFolder(cloud)
        return Fixture(root: root, cloud: cloud, file: file)
    }

    private func journal(of device: String, in cloud: URL) -> URL {
        cloud.appending(path: "state").appending(path: "\(device).jsonl")
    }

    private func device(_ id: String) {
        UserDefaults.standard.set(id, forKey: "deviceID")
    }

    private var target: AnnotationTarget {
        AnnotationTarget(materialID: "material", piece: 0, text: "First paragraph.")
    }

    func testARecordedChangeGoesToTheJournalAndIsReadBackOnce() async throws {
        let fixture = try await makeFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            UserDefaults.standard.removeObject(forKey: "deviceID")
        }

        device("phone")
        let phone = JournalSync(file: fixture.file)
        phone.record(.library(.mark(.highlight, target)))
        try await phone.flush()
        let written = try String(contentsOf: journal(of: "phone", in: fixture.cloud), encoding: .utf8)
        XCTAssertEqual(written.split(separator: "\n").count, 1)

        device("tablet")
        let tablet = JournalSync(file: fixture.file)
        try await tablet.load()
        let first = try await tablet.pendingRead()
        XCTAssertEqual(first.events.count, 1)
        let second = try await tablet.pendingRead()
        XCTAssertEqual(second.events.count, 1)
        tablet.commit(applied: second.applied)
        try await tablet.save()
        let third = JournalSync(file: fixture.file)
        try await third.load()
        let after = try await third.pendingRead()
        XCTAssertEqual(after.events.count, 0)
    }

    func testAChangeThatDidNotReachTheDiskWaitsForTheNextWrite() async throws {
        let fixture = try await makeFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            UserDefaults.standard.removeObject(forKey: "deviceID")
        }

        let state = fixture.cloud.appending(path: "state")
        try Data().write(to: state)
        device("phone")
        let phone = JournalSync(file: fixture.file)
        phone.record(.library(.mark(.highlight, target)))
        do {
            try await phone.flush()
            XCTFail("The write should have failed while the state folder is a file")
        } catch {}
        try FileManager.default.removeItem(at: state)
        try await phone.flush()
        let written = try String(contentsOf: journal(of: "phone", in: fixture.cloud), encoding: .utf8)
        XCTAssertEqual(written.split(separator: "\n").count, 1)
    }

    func testAnUnreadJournalIsNotConsumedUntilItIsCommitted() async throws {
        let fixture = try await makeFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            UserDefaults.standard.removeObject(forKey: "deviceID")
        }

        device("phone")
        let phone = JournalSync(file: fixture.file)
        phone.record(.library(.mark(.highlight, target)))
        try await phone.flush()

        device("tablet")
        let tablet = JournalSync(file: fixture.file)
        try await tablet.load()
        let read = try await tablet.pendingRead()
        let events = read.events
        XCTAssertEqual(events.count, 1)

        let again = try await tablet.pendingRead()
        XCTAssertEqual(again.events.count, 1)

        let merged = tablet.merging(events, into: LibrarySnapshot(), ReadingProgress())
        tablet.commit(merged.sync, applied: read.applied)
        try await tablet.save()

        let reloaded = JournalSync(file: fixture.file)
        try await reloaded.load()
        let after = try await reloaded.pendingRead()
        XCTAssertEqual(after.events.count, 0)
    }

    func testMergingAppliesAnotherDevicesChange() async throws {
        let fixture = try await makeFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            UserDefaults.standard.removeObject(forKey: "deviceID")
        }

        device("phone")
        let phone = JournalSync(file: fixture.file)
        phone.record(.library(.mark(.highlight, target)))
        try await phone.flush()

        device("tablet")
        let tablet = JournalSync(file: fixture.file)
        try await tablet.load()
        let read = try await tablet.pendingRead()
        let events = read.events
        let merged = tablet.merging(events, into: LibrarySnapshot(), ReadingProgress())
        XCTAssertEqual(merged.catalog.annotations.count, 1)
        XCTAssertEqual(merged.catalog.annotations.first?.text, "First paragraph.")
    }

    func testOwnJournalIsReadBackWhenSyncKnowledgeIsLost() async throws {
        let fixture = try await makeFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            UserDefaults.standard.removeObject(forKey: "deviceID")
        }

        device("phone")
        let phone = JournalSync(file: fixture.file)
        phone.record(.progress(.setRead(true, itemID: "article:one")))
        try await phone.flush()

        let recovered = JournalSync(file: fixture.file)
        let read = try await recovered.pendingRead()
        XCTAssertEqual(read.events.count, 1)
        let merged = recovered.merging(read.events, into: LibrarySnapshot(), ReadingProgress())
        XCTAssertEqual(merged.progress.readings["article:one"]?.isRead, true)
    }
}
