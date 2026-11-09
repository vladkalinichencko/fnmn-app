import Foundation
import Testing
@testable import FNMNCore

@Test func aReadingModeEventIsWrittenAndReadBack() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
    let file = LibraryFile(url: root.appending(path: "library"), cache: root.appending(path: "cache"))
    await file.useCloudFolder(cloud)

    let event = ReadingModeEvent(
        itemID: "article:one", mode: .rsvp, wordsPerMinute: 300, pauses: SpeedPauseProfile(.slight).json,
        words: 120, backs: 3, startedAt: Date(timeIntervalSince1970: 10), endedAt: Date(timeIntervalSince1970: 70)
    )
    try await file.appendReadingMode(event, device: "phone")
    try await file.appendReadingMode(event, device: "phone")

    let read = try await file.readingModes(device: "phone")
    #expect(read == [event, event])
    #expect(try await file.readingModes(device: "pad").isEmpty)
}
