@testable import FNMNCore
import Foundation
import Testing

private let article = ImportPackage(
    material: Material(id: "article:https://example.com/a", kind: .article, title: "A", sourceURL: URL(string: "https://example.com/a")!),
    sections: [Section(id: "s1", parentID: nil, title: "Start", level: 1, firstBlockID: "b1")],
    blocks: [Block(id: "b1", sectionID: "s1", kind: .paragraph, html: "<p>Text</p>")],
    folders: ["Inbox"]
)

@Test func repeatedImportUpdatesOneMaterialAndMergesFolders() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article)
    let second = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, folders: ["Papers"])
    try library.importPackage(second)
    #expect(library.packages.count == 1)
    #expect(library.packages[0].folders == ["Inbox", "Papers"])
}

@Test func positionAndNoteSurviveDiskRoundTrip() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory.appending(path: "library.json"))
    var library = LibrarySnapshot()
    try library.importPackage(article)
    library.positions[article.material.id] = ReadingPosition(blockID: "b1", textOffset: 12)
    library.notes.append(Note(materialID: article.material.id, blockID: "b1", text: "Remember this"))
    try await file.save(library)
    #expect(try await file.load() == library)
}

@Test func staleVideoEventCannotMoveReaderBackToOldBlock() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article)
    library.positions[article.material.id] = ReadingPosition(blockID: "next")
    let accepted = library.recordVideoTime(materialID: article.material.id, blockID: "b1", seconds: 42.125)
    #expect(!accepted)
    #expect(library.positions[article.material.id] == ReadingPosition(blockID: "next"))
}
