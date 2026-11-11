@testable import FNMNCore
import Foundation
import Testing

private func package(
    id: String,
    folders: [String] = [],
    source: URL? = nil,
    kind: Material.Kind = .article
) -> ImportPackage {
    ImportPackage(
        material: Material(
            id: id,
            kind: kind,
            title: id,
            sourceURL: source ?? URL(string: "https://example.com/\(id)")!
        ),
        sections: [],
        blocks: [],
        folders: folders,
        body: "Body text for \(id)."
    )
}

private func libraryEvent(_ seconds: TimeInterval, _ change: LibraryChange) -> JournalEvent {
    JournalEvent(time: Date(timeIntervalSinceReferenceDate: seconds), change: .library(change))
}

private func mergeLibrary(_ events: [JournalEvent], into snapshot: LibrarySnapshot) -> LibrarySnapshot {
    merge(events, into: snapshot, ReadingProgress(), sync: JournalKnowledge()).catalog
}

@Test func aFirstDeliveryLearnsItsFolders() throws {
    var library = LibrarySnapshot()
    try library.importPackage(package(id: "article:new", folders: ["Suggested"]), at: .now)
    #expect(library.albums(of: "article:new") == ["Suggested"])
}

@Test func aPlacementRecordedBeforeItsDeliveryKeepsTheDefaultFoldersOut() throws {
    let id = "article:late"
    var library = mergeLibrary([libraryEvent(1, .addToCollection("Rendering", itemIDs: [id]))], into: LibrarySnapshot())
    #expect(library.articles.isEmpty)
    try library.importPackage(package(id: id, folders: ["Suggested"]), at: .now)
    #expect(library.albums(of: id) == ["Rendering"])
}

@Test func anItemTakenOutOfEveryAlbumStaysOutWhenTheDeliveryComesAgain() throws {
    let id = "article:a"
    var library = LibrarySnapshot()
    try library.importPackage(package(id: id, folders: ["Suggested"]), at: .now)
    library = try library.applying(.removeFromCollection("Suggested", itemID: id))
    #expect(library.placements[id]?.isEmpty == true)
    try library.importPackage(package(id: id, folders: ["Suggested"]), at: .now)
    #expect(library.albums(of: id).isEmpty)
}

@Test func deletingAnItemForgetsItsPlacementDecision() throws {
    let id = "article:d"
    var library = LibrarySnapshot()
    try library.importPackage(package(id: id, folders: ["Suggested"]), at: .now)
    library = try library.applying(.removeFromCollection("Suggested", itemID: id))
    library = try library.applying(.delete(itemID: id))
    try library.importPackage(package(id: id, folders: ["Suggested"]), at: .now)
    #expect(library.albums(of: id) == ["Suggested"])
}

@Test func anItemWhoseOnlyAlbumWasDeletedStaysUnsortedOnReimport() throws {
    let id = "article:e"
    var library = LibrarySnapshot()
    try library.importPackage(package(id: id, folders: ["Suggested"]), at: .now)
    library = try library.applying(.deleteCollection("Suggested"))
    #expect(library.placements[id]?.isEmpty == true)
    try library.importPackage(package(id: id, folders: ["Suggested"]), at: .now)
    #expect(library.albums(of: id).isEmpty)
}

@Test func aLinkStubHandsItsAlbumToTheRealArticle() throws {
    let url = try #require(URL(string: "https://example.com/story"))
    var library = LibrarySnapshot()
    try library.importPackage(.link(url), at: .now)
    let linkID = "link:\(url.absoluteString)"
    library = try library.applying(.addToCollection("Reading", itemIDs: [linkID]))
    try library.importPackage(package(id: "article:real", folders: ["Suggested"], source: url), at: .now)
    #expect(library.albums(of: "article:real") == ["Reading"])
    #expect(library.articles.count == 1)
}

@Test func aLinkStubHandsItsUnsortedDecisionToTheRealArticle() throws {
    let url = try #require(URL(string: "https://example.com/quiet"))
    var library = LibrarySnapshot()
    try library.importPackage(.link(url), at: .now)
    let linkID = "link:\(url.absoluteString)"
    library = try library.applying(.addToCollection("Reading", itemIDs: [linkID]))
    library = try library.applying(.removeFromCollection("Reading", itemID: linkID))
    try library.importPackage(package(id: "article:real2", folders: ["Suggested"], source: url), at: .now)
    #expect(library.albums(of: "article:real2").isEmpty)
    #expect(library.articles.count == 1)
}

@Test func anAlbumCreatedOnTwoDevicesIsOneAlbum() throws {
    let first = mergeLibrary([libraryEvent(1, .createCollection("Theory"))], into: LibrarySnapshot())
    #expect(first.albums == ["Theory"])
    let second = mergeLibrary([libraryEvent(2, .createCollection("Theory"))], into: first)
    #expect(second.albums == ["Theory"])
}

@Test func aRenameOntoAnExistingAlbumKeepsTheSourceName() throws {
    var library = LibrarySnapshot()
    library.albums = ["Old", "Taken"]
    library.placements["article:x"] = ["Old"]
    let merged = mergeLibrary([libraryEvent(1, .renameCollection("Old", to: "Taken"))], into: library)
    #expect(merged.albums == ["Old", "Taken"])
    #expect(merged.albums(of: "article:x") == ["Old"])
}

@Test func aRenameToAFreshNameMovesTheAlbumsAndPlacements() throws {
    var library = LibrarySnapshot()
    library.albums = ["Old"]
    library.placements["article:x"] = ["Old"]
    let merged = mergeLibrary([libraryEvent(1, .renameCollection("Old", to: "New"))], into: library)
    #expect(merged.albums == ["New"])
    #expect(merged.albums(of: "article:x") == ["New"])
}

@Test func twoDevicesConvergeOnTheSamePlacementsRegardlessOfOrder() throws {
    let id = "article:both"
    let unsort = libraryEvent(10, .removeFromCollection("Suggested", itemID: id))
    let place = libraryEvent(5, .addToCollection("Reading", itemIDs: [id]))
    let forward = mergeLibrary([place, unsort], into: LibrarySnapshot())
    let backward = mergeLibrary([unsort, place], into: LibrarySnapshot())
    #expect(forward.placements == backward.placements)
    #expect(forward.placements[id] == ["Reading"])
}
