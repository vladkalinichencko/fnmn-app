@testable import FNMNCore
import Foundation
import Testing

private let paper = ImportPackage(
    material: Material(id: "article:paper", kind: .article, title: "Paper", sourceURL: URL(string: "https://example.com/paper")!),
    sections: [],
    blocks: [],
    body: "First paragraph.\n\nSecond paragraph."
)

private func library() throws -> LibrarySnapshot {
    var library = LibrarySnapshot()
    try library.importPackage(paper, at: .now)
    return library
}

@Test func anotherDevicesChangesArriveOnceAndInTimeOrder() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    let phone = LibraryFile(url: root.appending(path: "phone"))
    let tablet = LibraryFile(url: root.appending(path: "tablet"))
    await phone.useCloudFolder(cloud)
    await tablet.useCloudFolder(cloud)

    let target = AnnotationTarget(materialID: paper.material.id, piece: 0, text: "First paragraph.")
    let changes: [JournalEvent.Change] = [
        .progress(.open(itemID: paper.material.id)),
        .progress(.savePosition(.piece(1), itemID: paper.material.id, progress: 1)),
        .library(.createAlbum("Later")),
        .library(.addToAlbum("Later", itemIDs: [paper.material.id])),
        .library(.mark(.highlight, target)),
    ]
    let events = changes.enumerated().flatMap { JournalEvent.events(for: $1, at: Date(timeIntervalSinceReferenceDate: Double($0))) }
    try await phone.appendJournal(events, device: "phone")

    let unread = try await tablet.unreadJournalEvents(except: "tablet", sync: JournalSync())
    #expect(unread.events == events)
    var sync = JournalSync()
    sync.applied = unread.applied
    let merged = merge(unread.events, into: try library(), ReadingProgress(), sync: sync)
    #expect(merged.progress.positions[paper.material.id]?.pieceIndex == 1)
    #expect(merged.catalog.albums(of: paper.material.id) == ["Later"])
    #expect(merged.catalog.annotations.map(\.quote) == ["First paragraph."])
    #expect(try await tablet.unreadJournalEvents(except: "tablet", sync: merged.sync).events.isEmpty)
    #expect(try await phone.unreadJournalEvents(except: "phone", sync: JournalSync()).events.isEmpty)
}

@Test func theLatestPlaceWinsWhicheverDeviceItCameFrom() throws {
    var sync = JournalSync()
    let mine = JournalEvent(time: Date(timeIntervalSinceReferenceDate: 20), change: .progress(.savePosition(.piece(5), itemID: paper.material.id, progress: 0.5)))
    sync.record(mine)
    let progress = ReadingProgress().applying(.savePosition(.piece(5), itemID: paper.material.id, progress: 0.5))
    let older = JournalEvent(time: Date(timeIntervalSinceReferenceDate: 10), change: .progress(.savePosition(.piece(1), itemID: paper.material.id, progress: 0.1)))
    let newer = JournalEvent(time: Date(timeIntervalSinceReferenceDate: 30), change: .progress(.savePosition(.piece(9), itemID: paper.material.id, progress: 0.9)))
    #expect(merge([older], into: try library(), progress, sync: sync).progress.positions[paper.material.id]?.pieceIndex == 5)
    #expect(merge([older, newer], into: try library(), progress, sync: sync).progress.positions[paper.material.id]?.pieceIndex == 9)
}

@Test func aMaterialDeletedElsewhereTakesItsProgressWithIt() throws {
    let progress = ReadingProgress().applying(.savePosition(.piece(1), itemID: paper.material.id, progress: 0.5))
    let deleted = JournalEvent(time: .now, change: .library(.delete(itemID: paper.material.id)))
    let merged = merge([deleted], into: try library(), progress, sync: JournalSync())
    #expect(merged.catalog.articles.isEmpty)
    #expect(merged.progress == ReadingProgress())
}
