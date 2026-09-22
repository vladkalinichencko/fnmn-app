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

@Test func importKeepsTheMarkdownBody() throws {
    var library = LibrarySnapshot()
    let packaged = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, folders: article.folders, body: "A $x$ line.")
    try library.importPackage(packaged)
    let renamed = library.renameFolder(from: "Inbox", to: "Later")
    #expect(renamed)
    #expect(library.packages[0].body == "A $x$ line.")
}

@Test func positionAndNoteSurviveDiskRoundTrip() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory.appending(path: "library.json"))
    var library = LibrarySnapshot()
    try library.importPackage(article)
    library.positions[article.material.id] = ReadingPosition(blockID: "b1", textOffset: 12)
    library.notes.append(Note(materialID: article.material.id, blockID: "piece:4", text: "Remember this"))
    try await file.save(library)
    let loaded = try await file.load()
    #expect(loaded.notes.isEmpty)
    #expect(loaded.positions[article.material.id]?.blockID == "b1")
    #expect(loaded.highlights.contains { $0.caption == "Remember this" && $0.piece == 4 && $0.mark == nil })
}

private let laterArticle = ImportPackage(
    material: Material(id: "article:https://example.com/b", kind: .article, title: "B", sourceURL: URL(string: "https://example.com/b")!),
    sections: [Section(id: "s1", parentID: nil, title: "Start", level: 1, firstBlockID: "b1")],
    blocks: [Block(id: "b1", sectionID: "s1", kind: .paragraph, html: "<p>Text</p>")]
)

@Test func continueChoosesMostRecentlyOpenedMaterial() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article)
    try library.importPackage(laterArticle)
    library.positions[article.material.id] = ReadingPosition(blockID: "b1")
    library.positions[laterArticle.material.id] = ReadingPosition(blockID: "b1")
    library.recordOpening(materialID: article.material.id, at: Date(timeIntervalSinceReferenceDate: 1))
    library.recordOpening(materialID: laterArticle.material.id, at: Date(timeIntervalSinceReferenceDate: 2))
    #expect(library.continuedPackage?.material.id == laterArticle.material.id)
}

@Test func continueFallsBackToSavedPositionWhenNothingWasOpened() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article)
    try library.importPackage(laterArticle)
    library.positions[article.material.id] = ReadingPosition(blockID: "b1")
    library.positions[laterArticle.material.id] = ReadingPosition(blockID: "b1")
    #expect(library.continuedPackage?.material.id == article.material.id)
}

@Test func openingDoesNotMarkMaterialRead() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article)
    library.recordOpening(materialID: article.material.id, at: Date(timeIntervalSinceReferenceDate: 1))
    #expect(library.readings[article.material.id]?.isRead == false)
}

@Test func openingAndReadStateSurviveDiskRoundTrip() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory.appending(path: "library.json"))
    var library = LibrarySnapshot()
    try library.importPackage(article)
    library.recordOpening(materialID: article.material.id, at: Date(timeIntervalSinceReferenceDate: 10))
    library.setRead(true, materialID: article.material.id)
    try await file.save(library)
    #expect(try await file.load() == library)
}

@Test func oldStateWithoutReadingsStillLoads() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(#"{"positions":{},"notes":[],"folders":[]}"#.utf8)
        .write(to: directory.appending(path: "state.json"))
    let snapshot = try await LibraryFile(url: directory).load()
    #expect(snapshot.readings.isEmpty)
    #expect(snapshot.continuedPackage == nil)
}

@Test func staleVideoEventCannotMoveReaderBackToOldBlock() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article)
    library.positions[article.material.id] = ReadingPosition(blockID: "next")
    let accepted = library.recordVideoTime(materialID: article.material.id, blockID: "b1", seconds: 42.125)
    #expect(!accepted)
    #expect(library.positions[article.material.id] == ReadingPosition(blockID: "next"))
}

private var sampleBook: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "fixtures/books/principles-of-deep-learning-theory")
}

@Test func bookCatalogInspectsValidatedFixture() throws {
    let imported = try BookCatalog.inspect(from: sampleBook)
    #expect(imported.record.metadata.title == "The Principles of Deep Learning Theory")
    #expect(imported.record.metadata.toc.count == 223)
    #expect(imported.validation.headings == 223)
    #expect(imported.validation.images == 10)
    #expect(imported.validation.errors.isEmpty)
    #expect(imported.imagePaths.count == 10)
    #expect(imported.footnoteIDs.count == 313)
}

@Test func bookImportRejectsValidationErrors() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.copyItem(at: sampleBook, to: directory)
    try Data(#"{"headings":0,"images":0,"errors":["missing_images"]}"#.utf8)
        .write(to: directory.appending(path: "validation.json"))
    #expect(throws: BookError.rejected(["missing_images"])) {
        try BookCatalog.inspect(from: directory)
    }
}

@Test func bookImportCopiesCatalogIntoLibrary() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory)
    let imported = try BookCatalog.inspect(from: sampleBook)
    var library = LibrarySnapshot()
    library.importBook(imported.record)
    try await file.copyBook(from: sampleBook, named: imported.record.directoryName)
    try await file.saveState(library)
    let loaded = try await file.load()
    #expect(loaded.books.count == 1)
    #expect(loaded.books[0].metadata.toc.count == 223)
    let copied = directory.appending(path: "books").appending(path: imported.record.directoryName)
    #expect(FileManager.default.fileExists(atPath: copied.appending(path: "content.md").path))
    for image in imported.imagePaths {
        #expect(FileManager.default.fileExists(atPath: copied.appending(path: image).path))
    }
}

@Test func oldStateWithoutBooksStillLoads() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(#"{"positions":{},"notes":[],"folders":[]}"#.utf8)
        .write(to: directory.appending(path: "state.json"))
    let snapshot = try await LibraryFile(url: directory).load()
    #expect(snapshot.books.isEmpty)
}

private let namedArticle = ImportPackage(
    material: Material(id: "article:https://example.com/search", kind: .article, title: "Kernel Methods", sourceURL: URL(string: "https://example.com/search")!, byline: "Alice"),
    sections: [Section(id: "s1", parentID: nil, title: "NTK", level: 1, firstBlockID: "b1")],
    blocks: [Block(id: "b1", sectionID: "s1", kind: .paragraph, html: "<p>hidden body text</p>")],
    folders: ["Papers"]
)

private let namedBook = BookRecord(
    metadata: BookMetadata(
        title: "The Principles of Deep Learning Theory",
        subtitle: "An Effective Theory Approach",
        authors: ["Daniel A. Roberts"],
        contributors: nil,
        language: "en",
        sourceName: "principles-of-deep-learning-theory.pdf",
        schemaVersion: 1,
        contentFile: "content.md",
        assetsDirectory: "assets",
        toc: [BookTOCEntry(ordinal: 1, level: 1, title: "Effective Theory")]
    )
)

@Test func librarySearchMatchesCatalogFieldsAndIgnoresBody() throws {
    var library = LibrarySnapshot()
    try library.importPackage(namedArticle)
    library.importBook(namedBook)
    #expect(library.matchingPackages("").map(\.material.id) == [namedArticle.material.id])
    #expect(library.matchingBooks(" ").map(\.id) == [namedBook.id])
    #expect(library.matchingPackages("kernel").map(\.material.id) == [namedArticle.material.id])
    #expect(library.matchingPackages("Alice").map(\.material.id) == [namedArticle.material.id])
    #expect(library.matchingPackages("Papers").map(\.material.id) == [namedArticle.material.id])
    #expect(library.matchingPackages("NTK").map(\.material.id) == [namedArticle.material.id])
    #expect(library.matchingPackages("hidden body text").isEmpty)
    #expect(library.matchingBooks("roberts").map(\.id) == [namedBook.id])
    #expect(library.matchingBooks("Effective Theory").map(\.id) == [namedBook.id])
    #expect(library.matchingPackages("xyzzy").isEmpty)
    #expect(library.matchingBooks("xyzzy").isEmpty)
}

@Test func captureRouteNamesSourceFromLinkOrPDF() {
    #expect(CaptureRoute.source(for: URL(string: "https://example.com/post")!) == .web)
    #expect(CaptureRoute.source(for: URL(string: "https://youtu.be/abc")!) == .youtube)
    #expect(CaptureRoute.source(for: URL(string: "https://www.youtube.com/watch?v=abc")!) == .youtube)
    #expect(CaptureRoute.source(for: URL(string: "https://arxiv.org/abs/1706.03762")!) == .arxiv)
    #expect(CaptureRoute.source(for: URL(string: "https://x.com/someone/status/1")!) == .x)
    #expect(CaptureRoute.source(for: URL(string: "https://twitter.com/someone/status/1")!) == .x)
    #expect(CaptureRoute.source(for: URL(string: "https://name.substack.com/p/hello")!) == .substack)
    #expect(CaptureRoute.source(for: URL(string: "https://chatgpt.com/share/abc")!) == .chatgpt)
    #expect(CaptureRoute.source(for: URL(string: "https://example.com/paper.pdf")!) == .pdf)
    #expect(CaptureRoute.source(for: URL(string: "https://arxiv.org/pdf/1706.03762.pdf")!) == .arxiv)
    #expect(CaptureRoute.source(for: URL(string: "ftp://example.com/a")!) == nil)
    #expect(CaptureError.unprepared(.youtube).errorDescription?.contains("YouTube") == true)
}

@Test func shareHandoffRoundTripsAnHTTPLink() {
    let article = URL(string: "https://arxiv.org/abs/1706.03762")!
    let handoff = CaptureHandoff.link(for: article)
    #expect(CaptureHandoff.sharedURL(from: handoff!) == article)
    #expect(CaptureHandoff.sharedURL(from: URL(string: "fnmn://add?url=ftp://example.com")!) == nil)
    #expect(CaptureHandoff.sharedURL(from: URL(string: "https://example.com")!) == nil)
}

@Test func oldHighlightWithoutMarkDecodesAsHighlight() throws {
    let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","materialID":"article:1","piece":2,"quote":"old quote","caption":"kept"}"#.utf8)
    let highlight = try JSONDecoder().decode(Highlight.self, from: data)
    #expect(highlight.mark == .highlight)
    #expect(highlight.quote == "old quote")
    #expect(highlight.caption == "kept")
}

@Test func aSecondQuoteOnTheSameParagraphStays() {
    let first = applyingAnnotation(to: [], materialID: "article:1", piece: 2, quote: "one phrase", caption: nil, mark: .highlight)
    let second = applyingAnnotation(to: first, materialID: "article:1", piece: 2, quote: "another phrase", caption: nil, mark: .strikethrough)
    #expect(second.map(\.quote) == ["one phrase", "another phrase"])
    let noted = applyingAnnotation(to: second, materialID: "article:1", piece: 2, quote: "one phrase", caption: "a thought", mark: nil)
    #expect(noted.count == 2)
    #expect(noted[0].caption == "a thought")
    #expect(noted[0].mark == .highlight)
}

@Test func noteOnlyHighlightRoundTripsWithNilMark() throws {
    let note = Highlight(materialID: "article:1", piece: 0, quote: "paragraph text", caption: "my note", mark: nil)
    let data = try JSONEncoder().encode(note)
    let decoded = try JSONDecoder().decode(Highlight.self, from: data)
    #expect(decoded.mark == nil)
    #expect(decoded.caption == "my note")
    #expect(decoded.quote == "paragraph text")
}

@Test func albumKeepsACardInEveryFolderItWasDroppedInto() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article)
    library.place(materialID: namedBook.id, in: "PDF")
    library.importBook(namedBook)
    library.place(materialID: article.material.id, in: "Web")
    library.place(materialID: namedBook.id, in: "Reading")
    #expect(library.packages(in: "Inbox").map(\.material.id) == [article.material.id])
    #expect(library.packages(in: "Web").map(\.material.id) == [article.material.id])
    #expect(library.books(in: "PDF").map(\.id) == [namedBook.id])
    #expect(library.books(in: "Reading").map(\.id) == [namedBook.id])
    let renamed = library.renameFolder(from: "Inbox", to: "Papers")
    #expect(renamed)
    #expect(library.packages(in: "Inbox").isEmpty)
    #expect(library.packages(in: "Papers").map(\.material.id) == [article.material.id])
    #expect(library.packages(in: "Web").map(\.material.id) == [article.material.id])
    let collided = library.renameFolder(from: "Papers", to: "Web")
    #expect(!collided)
    #expect(library.packages(in: "Papers").map(\.material.id) == [article.material.id])
}
