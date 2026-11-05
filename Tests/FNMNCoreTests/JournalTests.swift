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

    let unread = try await tablet.unreadJournalEvents(except: "tablet", sync: JournalKnowledge())
    #expect(unread.events == events)
    var sync = JournalKnowledge()
    sync.applied = unread.applied
    let merged = merge(unread.events, into: try library(), ReadingProgress(), sync: sync)
    #expect(merged.progress.positions[paper.material.id]?.pieceIndex == 1)
    #expect(merged.catalog.albums(of: paper.material.id) == ["Later"])
    #expect(merged.catalog.annotations.map(\.text) == ["First paragraph."])
    #expect(try await tablet.unreadJournalEvents(except: "tablet", sync: merged.sync).events.isEmpty)
    #expect(try await phone.unreadJournalEvents(except: "phone", sync: JournalKnowledge()).events.isEmpty)
}

@Test func aLongJournalFoldsIntoANewGenerationThatGivesTheSameState() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    let phone = LibraryFile(url: root.appending(path: "phone"))
    let tablet = LibraryFile(url: root.appending(path: "tablet"))
    await phone.useCloudFolder(cloud)
    await tablet.useCloudFolder(cloud)
    let target = AnnotationTarget(materialID: paper.material.id, piece: 0, text: "First paragraph.")
    let places = (0..<5).map { JournalEvent(time: Date(timeIntervalSinceReferenceDate: Double($0)), change: .progress(.savePosition(.piece($0 % 2), itemID: paper.material.id, progress: 0.5))) }
    let mark = JournalEvent(time: Date(timeIntervalSinceReferenceDate: 2.5), change: .library(.mark(.highlight, target)))

    try await phone.appendJournal(Array(places.prefix(3)), device: "phone", compactingAfter: 4)
    let early = try await tablet.unreadJournalEvents(except: "tablet", sync: JournalKnowledge())
    var sync = JournalKnowledge()
    sync.applied = early.applied
    let first = merge(early.events, into: try library(), ReadingProgress(), sync: sync)

    try await phone.appendJournal([mark] + Array(places.suffix(2)), device: "phone", compactingAfter: 4)
    let files = try FileManager.default.contentsOfDirectory(atPath: cloud.appending(path: "state").path)
    #expect(files.count == 1 && files[0].hasPrefix("phone.") && files[0] != "phone.jsonl")
    let late = try await tablet.unreadJournalEvents(except: "tablet", sync: first.sync)
    #expect(late.events.count == 2)
    var lateSync = first.sync
    lateSync.applied = late.applied
    let caughtUp = merge(late.events, into: first.catalog, first.progress, sync: lateSync)
    let whole = merge(places + [mark], into: try library(), ReadingProgress(), sync: JournalKnowledge())
    #expect(caughtUp.progress == whole.progress)
    #expect(caughtUp.catalog.annotations.map(\.marks) == whole.catalog.annotations.map(\.marks))
}

@Test func theLatestPlaceWinsWhicheverDeviceItCameFrom() throws {
    var sync = JournalKnowledge()
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
    let merged = merge([deleted], into: try library(), progress, sync: JournalKnowledge())
    #expect(merged.catalog.articles.isEmpty)
    #expect(merged.progress == ReadingProgress())
}

private func stamp(_ seconds: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

@Test func aResetWipesWhatCameBeforeItAndKeepsWhatCameAfter() throws {
    let id = paper.material.id
    let events = [
        JournalEvent(time: stamp(10), change: .progress(.savePosition(.piece(1), itemID: id, progress: 0.5))),
        JournalEvent(time: stamp(20), change: .progress(.reset(itemID: id))),
        JournalEvent(time: stamp(30), change: .progress(.savePosition(.piece(0), itemID: id, progress: 0.1))),
    ]
    let merged = merge(events, into: try library(), ReadingProgress(), sync: JournalKnowledge())
    #expect(merged.progress.positions[id] == .piece(0))
}

@Test func aReadingLineFollowsTheLatestDeviceAndAResetBeforeIt() throws {
    let id = paper.material.id
    let line = ReadingLine(piece: 1, fraction: 0.4)
    let events = [
        JournalEvent(time: stamp(10), change: .progress(.line(ReadingLine(piece: 0, fraction: 0.2), itemID: id))),
        JournalEvent(time: stamp(20), change: .progress(.reset(itemID: id))),
        JournalEvent(time: stamp(30), change: .progress(.line(line, itemID: id))),
    ]
    #expect(merge(events, into: try library(), ReadingProgress(), sync: JournalKnowledge()).progress.lines[id] == line)
    #expect(merge(Array(events.prefix(2)), into: try library(), ReadingProgress(), sync: JournalKnowledge()).progress.lines[id] == nil)
}

@Test func aResetFromAnotherDeviceLeavesWhatThisDeviceReadAfterIt() throws {
    let id = paper.material.id
    var sync = JournalKnowledge()
    var progress = ReadingProgress()
    progress = progress.applying(.savePosition(.piece(1), itemID: id, progress: 0.5))
    sync.record(JournalEvent(time: stamp(30), change: .progress(.savePosition(.piece(1), itemID: id, progress: 0.5))))
    let reset = JournalEvent(time: stamp(20), change: .progress(.reset(itemID: id)))
    let merged = merge([reset], into: try library(), progress, sync: sync)
    #expect(merged.progress.positions[id] == .piece(1))
}

@Test func anOlderPlateFromAnotherDeviceDoesNotUndoAResetHere() throws {
    let id = paper.material.id
    var sync = JournalKnowledge()
    sync.record(JournalEvent(time: stamp(20), change: .progress(.reset(itemID: id))))
    let late = JournalEvent(time: stamp(10), change: .progress(.savePosition(.piece(1), itemID: id, progress: 0.5)))
    let merged = merge([late], into: try library(), ReadingProgress(), sync: sync)
    #expect(merged.progress.positions[id] == nil)
}

@Test func savedKnowledgeOfTheJournalsSurvivesTheDiskRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    let phone = LibraryFile(url: root.appending(path: "phone"))
    let tablet = LibraryFile(url: root.appending(path: "tablet"))
    await phone.useCloudFolder(cloud)
    await tablet.useCloudFolder(cloud)
    let target = AnnotationTarget(materialID: paper.material.id, piece: 0, text: "First paragraph.")
    let events = JournalEvent.events(for: .library(.mark(.highlight, target)), at: stamp(1))
    try await phone.appendJournal(events, device: "phone")

    // The tablet reads with the knowledge it saved last time, not with what it holds in memory.
    let known = try await tablet.loadSync()
    let unread = try await tablet.unreadJournalEvents(except: "tablet", sync: known)
    #expect(unread.events == events)
    var after = known
    after.applied = unread.applied
    let merged = merge(unread.events, into: try library(), ReadingProgress(), sync: after)
    try await tablet.saveSync(merged.sync)

    let reloaded = try await tablet.loadSync()
    #expect(reloaded == merged.sync)
    #expect(try await tablet.unreadJournalEvents(except: "tablet", sync: reloaded).events.isEmpty)
}

@Test func anAnnotationDeletedOnOneDeviceIsGoneOnTheOther() throws {
    let target = AnnotationTarget(materialID: paper.material.id, piece: 0, text: "First paragraph.")
    let marked = JournalEvent(time: stamp(1), change: .library(.mark(.highlight, target)))
    // The tablet took the phone's mark in and deletes what it now holds.
    let onTablet = merge([marked], into: try library(), ReadingProgress(), sync: JournalKnowledge())
    let removed = JournalEvent(time: stamp(2), change: .library(.removeAnnotation(onTablet.catalog.annotations[0].id)))
    // The phone made the mark itself and takes the tablet's deletion in.
    let onPhone = try library().applying(.mark(.highlight, target), at: stamp(1))
    let merged = merge([removed], into: onPhone, ReadingProgress(), sync: JournalKnowledge())
    #expect(merged.catalog.annotations.isEmpty)
}

@Test func aMarkThatArrivesLateDoesNotBringBackAnAnnotationDeletedHere() throws {
    let target = AnnotationTarget(materialID: paper.material.id, piece: 0, text: "First paragraph.")
    // The tablet marked the paragraph at 1; its journal reaches this device only after the annotation was deleted at 2.
    let marked = JournalEvent(time: stamp(1), change: .library(.mark(.highlight, target)))
    var catalog = try library().applying(.mark(.highlight, target), at: stamp(0.5))
    var sync = JournalKnowledge()
    let id = catalog.annotations[0].id
    catalog = try catalog.applying(.removeAnnotation(id), at: stamp(2))
    sync.record(JournalEvent(time: stamp(2), change: .library(.removeAnnotation(id))))
    let merged = merge([marked], into: catalog, ReadingProgress(), sync: sync)
    #expect(merged.catalog.annotations.isEmpty)
}
