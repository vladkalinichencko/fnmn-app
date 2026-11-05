import FNMNCore
import XCTest
@testable import FNMN

/// This device's journal: recording, writing, reading the other devices' lines, and merging them.
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
        let first = try await tablet.unread()
        XCTAssertEqual(first?.count, 1)
        let second = try await tablet.unread()
        XCTAssertNil(second)
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
        let unread = try await tablet.unread()
        let events = try XCTUnwrap(unread)
        let merged = tablet.merging(events, into: LibrarySnapshot(), ReadingProgress())
        XCTAssertEqual(merged.catalog.annotations.count, 1)
        XCTAssertEqual(merged.catalog.annotations.first?.text, "First paragraph.")
    }
}
