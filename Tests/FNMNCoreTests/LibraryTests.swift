@testable import FNMNCore
import Foundation
import Testing

private let article = ImportPackage(
    material: Material(id: "article:https://example.com/a", kind: .article, title: "A", sourceURL: URL(string: "https://example.com/a")!),
    sections: [Section(id: "s1", parentID: nil, title: "Start", level: 1, firstBlockID: "b1")],
    blocks: [Block(id: "b1", sectionID: "s1", kind: .paragraph, html: "<p>Text</p>")],
    folders: ["Inbox"]
)

@Test func repeatedImportKeepsTheReadersAlbums() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    let second = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, folders: ["Papers"])
    try library.importPackage(second, at: .now)
    #expect(library.articles.count == 1)
    #expect(library.albums(of: article.material.id) == ["Inbox"])
}

@Test func browserImportReplacesCollectionAlbumsWithReviewedOnes() throws {
    var library = LibrarySnapshot()
    let old = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, folders: ["Reading"])
    try library.importPackage(old, at: .now)
    library.retireAlbums(["Reading"])
    let reviewed = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, folders: ["ML Theory"])
    try library.importPackage(reviewed, at: .now)
    #expect(library.albums == ["ML Theory"])
    #expect(library.albums(of: article.material.id) == ["ML Theory"])
}

@Test func browserImportKeepsSourceOnlySitesAndPreparedMaterials() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let prepared = root.appending(path: "prepared")
    try FileManager.default.createDirectory(at: prepared.appending(path: "deliveries"), withIntermediateDirectories: true)
    let catalog = #"{"collections":[{"id":"reading","name":"Reading"}],"sources":[{"name":"Example","url":"https://example.com","kind":"site","saved_in":["reading"],"found_in":["reading"],"materials":[]},{"name":"Author","url":"https://example.org","kind":"author","saved_in":["reading"],"found_in":["reading"],"materials":[{"title":"A","url":"https://example.com/a","saved_in":["reading"],"found_in":["reading"]}]}]}"#
    try Data(catalog.utf8).write(to: prepared.appending(path: "catalog.json"))
    try writeDelivery(article, files: [("assets/p.png", Data("png".utf8))], to: prepared.appending(path: "deliveries/a.tar"))
    try Data(#"[{"url":"https://example.com/a","folders":["Web"]}]"#.utf8).write(to: prepared.appending(path: "index.json"))

    let file = LibraryFile(url: root.appending(path: "library"))
    let imported = try await file.storeBrowserLibrary(from: prepared, into: LibrarySnapshot())
    #expect(imported.browserCatalog?.sources.first?.materials.isEmpty == true)
    #expect(imported.browserCatalog?.sources.last?.materials.first?.savedURLs == [])
    #expect(imported.articles.map(\.material.id) == [article.material.id])
    let reloaded = try await file.load()
    #expect(reloaded.catalog.browserCatalog == imported.browserCatalog)
    let revision = imported.articleRevisions[article.material.id]
    #expect(try await file.article(article.material.id, revision: revision) == article)
    let picture = try #require(LibraryFile.articleFile(root: root.appending(path: "library"), materialID: article.material.id, path: "assets/p.png", revision: revision))
    #expect(try Data(contentsOf: picture) == Data("png".utf8))
}

@Test func aLinkTheMacCouldNotPrepareLandsInItsAlbum() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let prepared = root.appending(path: "prepared")
    try FileManager.default.createDirectory(at: prepared.appending(path: "deliveries"), withIntermediateDirectories: true)
    let catalog = #"{"collections":[],"sources":[{"name":"ACM","url":"https://dl.acm.org","kind":"site","saved_in":[],"found_in":[],"materials":[{"title":"Paper","url":"https://dl.acm.org/doi/1","saved_in":[],"found_in":[]}]}]}"#
    try Data(catalog.utf8).write(to: prepared.appending(path: "catalog.json"))
    try Data(#"[{"url":"https://dl.acm.org/doi/1","folders":["HCI"]}]"#.utf8).write(to: prepared.appending(path: "index.json"))
    let imported = try await LibraryFile(url: root.appending(path: "library")).storeBrowserLibrary(from: prepared, into: LibrarySnapshot())
    #expect(imported.items(inAlbum: "HCI").map(\.id) == ["link:https://dl.acm.org/doi/1"])
    #expect(imported.items(inAlbum: "HCI").first?.kind == .link)
}

@Test func importKeepsTheMarkdownBody() async throws {
    let file = LibraryFile(url: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let packaged = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, folders: article.folders, body: "A $x$ line.")
    var library = try await file.storeArticle(packaged, into: LibrarySnapshot())
    library = try library.applying(.renameAlbum("Inbox", to: "Later"))
    #expect(try await file.article(article.material.id, revision: library.articleRevisions[article.material.id]).body == "A $x$ line.")
    #expect(library.albums(of: article.material.id) == ["Later"])
}

@Test func deletingAnArticleRemovesItsFolder() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory)
    let delivery = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".tar")
    try writeDelivery(article, files: [("assets/pic.txt", Data("pic".utf8))], to: delivery)
    let stored = try await file.storeArticle(archive: delivery, into: LibrarySnapshot())
    let revision = stored.articleRevisions[article.material.id]
    let text = try #require(LibraryFile.articleFile(root: directory, materialID: article.material.id, path: "text.json", revision: revision))
    #expect(FileManager.default.fileExists(atPath: text.path))
    let deleted = try stored.applying(.delete(itemID: article.material.id))
    try await file.save(deleted, previous: stored)
    #expect(!FileManager.default.fileExists(atPath: LibraryFile.articleFolder(root: directory, materialID: article.material.id, revision: nil).path))
}

@Test func articlesInsideOnePackagesFileMoveToTheirFolders() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let packaged = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, body: "# Kernel\n\nA long enough opening paragraph that becomes the excerpt of this article.")
    try JSONEncoder().encode([packaged]).write(to: directory.appending(path: "packages.json"))
    let file = LibraryFile(url: directory)
    let loaded = try await file.load().catalog
    #expect(loaded.articles.map(\.material.id) == [article.material.id])
    #expect(loaded.articles[0].searchText.contains("kernel"))
    #expect(loaded.articles[0].excerpt?.hasPrefix("A long enough") == true)
    #expect(try await file.article(article.material.id, revision: nil) == packaged)
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "packages.json").path))
    #expect(try await file.load().catalog == loaded)
}

@Test func positionAndNoteSurviveDiskRoundTrip() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory.appending(path: "library.json"))
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    var progress = ReadingProgress()
    progress.positions[article.material.id] = ReadingPosition(blockID: "b1", textOffset: 12)
    try await file.save(library)
    try await file.saveProgress(progress)
    let stateURL = directory.appending(path: "library.json").appending(path: "state.json")
    var text = try String(contentsOf: stateURL, encoding: .utf8)
    let note = #"[{"id":"00000000-0000-0000-0000-000000000009","materialID":"\#(article.material.id)","blockID":"piece:4","text":"Remember this"}]"#
    if let brace = text.firstIndex(of: "{") {
        text.replaceSubrange(brace...brace, with: "{\"notes\":\(note),")
    }
    try Data(text.utf8).write(to: stateURL)
    let loaded = try await file.load()
    #expect(loaded.progress.positions[article.material.id]?.blockID == "b1")
    #expect(loaded.catalog.annotations.contains { $0.id == UUID(uuidString: "00000000-0000-0000-0000-000000000009") && $0.note == "Remember this" && $0.piece == 4 && $0.mark == nil })
    let saved = try String(contentsOf: stateURL, encoding: .utf8)
    #expect(!saved.contains("\"notes\""))
}

@Test func legacyBlockPositionBecomesAPiece() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory)
    let placed = ImportPackage(
        material: Material(id: "article:https://example.com/placed", kind: .article, title: "Placed", sourceURL: URL(string: "https://example.com/placed")!),
        sections: [Section(id: "s1", parentID: nil, title: "Hello", level: 1, firstBlockID: "b1")],
        blocks: [Block(id: "b1", sectionID: "s1", kind: .heading, html: "Hello")],
        body: "# Hello\n\nAfter"
    )
    var progress = ReadingProgress()
    progress.positions[placed.material.id] = ReadingPosition(blockID: "b1")
    try await file.saveProgress(progress)
    try JSONEncoder().encode([placed]).write(to: directory.appending(path: "packages.json"))
    let loaded = try await file.load()
    #expect(loaded.progress.positions[placed.material.id]?.pieceIndex == 0)
}

@Test func progressInsideOldStateMovesToItsOwnFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let stateURL = directory.appending(path: "state.json")
    try Data(#"{"positions":{"a":{"blockID":"piece:3","textOffset":0}},"readThrough":{"a":2},"readings":{"a":{"isRead":true}},"albums":["Later"]}"#.utf8)
        .write(to: stateURL)
    let file = LibraryFile(url: directory)
    let loaded = try await file.load()
    #expect(loaded.progress.positions["a"]?.pieceIndex == 3)
    #expect(loaded.progress.readThrough["a"] == 2)
    #expect(loaded.progress.readings["a"]?.isRead == true)
    #expect(loaded.catalog.albums == ["Later"])
    #expect(!(try String(contentsOf: stateURL, encoding: .utf8)).contains("positions"))
    #expect(try await file.load().progress == loaded.progress)
}

@Test func articleBodyImportsWithoutBlocks() throws {
    var library = LibrarySnapshot()
    let packaged = ImportPackage(
        material: article.material,
        sections: [],
        blocks: [],
        body: "# Hello\n\nText"
    )
    try library.importPackage(packaged, at: .now)
    #expect(library.articles[0].searchText.hasSuffix("\nhello"))
    #expect(throws: LibraryError.emptyDocument) {
        try library.importPackage(ImportPackage(material: laterArticle.material, sections: [], blocks: []), at: .now)
    }
}

private let laterArticle = ImportPackage(
    material: Material(id: "article:https://example.com/b", kind: .article, title: "B", sourceURL: URL(string: "https://example.com/b")!),
    sections: [Section(id: "s1", parentID: nil, title: "Start", level: 1, firstBlockID: "b1")],
    blocks: [Block(id: "b1", sectionID: "s1", kind: .paragraph, html: "<p>Text</p>")]
)

@Test func continueChoosesMostRecentlyOpenedMaterial() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    try library.importPackage(laterArticle, at: .now)
    var progress = ReadingProgress()
    progress.positions[article.material.id] = ReadingPosition(blockID: "b1")
    progress.positions[laterArticle.material.id] = ReadingPosition(blockID: "b1")
    progress = progress.applying(.open(itemID: article.material.id), at: Date(timeIntervalSinceReferenceDate: 1))
    progress = progress.applying(.open(itemID: laterArticle.material.id), at: Date(timeIntervalSinceReferenceDate: 2))
    #expect(library.continuedID(progress) == laterArticle.material.id)
}

@Test func continueFallsBackToSavedPositionWhenNothingWasOpened() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    try library.importPackage(laterArticle, at: .now)
    var progress = ReadingProgress()
    progress.positions[article.material.id] = ReadingPosition(blockID: "b1")
    progress.positions[laterArticle.material.id] = ReadingPosition(blockID: "b1")
    #expect(library.continuedID(progress) == article.material.id)
}

@Test func openingDoesNotMarkMaterialRead() {
    let progress = ReadingProgress().applying(.open(itemID: article.material.id), at: Date(timeIntervalSinceReferenceDate: 1))
    #expect(progress.readings[article.material.id]?.isRead == false)
}

@Test func openingAndReadStateSurviveDiskRoundTrip() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory.appending(path: "library.json"))
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    let progress = ReadingProgress()
        .applying(.open(itemID: article.material.id), at: Date(timeIntervalSinceReferenceDate: 10))
        .applying(.setRead(true, itemID: article.material.id))
    try await file.save(library)
    try await file.saveProgress(progress)
    let loaded = try await file.load()
    #expect(loaded.catalog == library)
    #expect(loaded.progress == progress)
}

@Test func oldStateWithoutReadingsStillLoads() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(#"{"positions":{},"notes":[],"folders":[]}"#.utf8)
        .write(to: directory.appending(path: "state.json"))
    let loaded = try await LibraryFile(url: directory).load()
    #expect(loaded.progress.readings.isEmpty)
    #expect(loaded.catalog.continuedID(loaded.progress) == nil)
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

@Test func aPickedPackageOrBookFolderIsStoredAndAPDFIsNot() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = LibraryFile(url: directory.appending(path: "library"))
    let picked = directory.appending(path: "a.json")
    try JSONEncoder().encode(article).write(to: picked)
    var library = try await file.storePicked(picked, into: LibrarySnapshot())
    library = try await file.storePicked(sampleBook, into: library)
    #expect(library.articles.map(\.material.id) == [article.material.id])
    #expect(library.books.count == 1)
    let pdf = directory.appending(path: "b.pdf")
    try Data("%PDF".utf8).write(to: pdf)
    await #expect(throws: CaptureError.unprepared(.pdf)) { try await file.storePicked(pdf, into: library) }
}

@Test func bookImportCopiesCatalogIntoLibrary() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory)
    let imported = try BookCatalog.inspect(from: sampleBook)
    let library = try await file.storeBook(imported.record, from: sampleBook, into: LibrarySnapshot())
    try await file.save(library)
    let loaded = try await file.load().catalog
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
    let snapshot = try await LibraryFile(url: directory).load().catalog
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
    try library.importPackage(namedArticle, at: .now)
    library.importBook(namedBook, at: .now)
    func ids(_ query: String) -> Set<String> { Set(library.items(matching: query).map(\.id)) }
    #expect(ids(" ") == [namedArticle.material.id, namedBook.id])
    #expect(ids("kernel") == [namedArticle.material.id])
    #expect(ids("Alice") == [namedArticle.material.id])
    #expect(ids("Papers") == [namedArticle.material.id])
    #expect(ids("NTK") == [namedArticle.material.id])
    #expect(ids("roberts") == [namedBook.id])
    #expect(ids("Effective Theory") == [namedBook.id])
    #expect(ids("hidden body text").isEmpty)
    #expect(ids("xyzzy").isEmpty)
    let headed = ImportPackage(
        material: Material(id: "article:headed", kind: .article, title: "Plain", sourceURL: URL(string: "https://example.com/headed")!),
        sections: [],
        blocks: [],
        body: "# Kernel Trick\n\nhidden body text"
    )
    try library.importPackage(headed, at: .now)
    #expect(ids("Kernel Trick") == ["article:headed"])
    #expect(ids("hidden body text").isEmpty)
}

@Test func captureRouteNamesSourceFromLinkOrPDF() throws {
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "fixtures/capture-sources.json")
    let rows = try JSONDecoder().decode([CaptureSourceRow].self, from: Data(contentsOf: fixture))
    for row in rows {
        #expect(CaptureRoute.source(for: row.url)?.rawValue == row.source)
    }
    #expect(CaptureError.unprepared(.youtube).errorDescription?.contains("YouTube") == true)
}

private struct CaptureSourceRow: Decodable {
    let url: URL
    let source: String?
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
    let annotation = try JSONDecoder().decode(Annotation.self, from: data)
    #expect(annotation.mark == .highlight)
    #expect(annotation.quote == "old quote")
    #expect(annotation.note == "kept")
}

private let paragraph = AnnotationTarget(materialID: "article:1", piece: 2, text: "one phrase and another phrase end here")

private func span(_ quote: String) -> AnnotationTarget {
    let range = (paragraph.text as NSString).range(of: quote)
    return AnnotationTarget(materialID: paragraph.materialID, piece: paragraph.piece, text: paragraph.text, span: TextSpan(start: range.location, length: range.length))
}

@Test func touchingHighlightsBecomeOneRecord() throws {
    var library = LibrarySnapshot()
    library = try library.applying(.mark(.highlight, span("one phrase")))
    library = try library.applying(.mark(.highlight, span("phrase and another")))
    #expect(library.annotations.map(\.quote) == ["one phrase and another"])
    library = try library.applying(.mark(.strikethrough, span("end")))
    #expect(library.annotations.count == 2)
}

@Test func theMenuOffersRemovalOnlyWhereAMarkIs() throws {
    var library = LibrarySnapshot()
    library = try library.applying(.mark(.highlight, span("another phrase")))
    #expect(annotationCommands(library.annotations, at: span("another")) == [.unmark(.highlight), .mark(.strikethrough)])
    #expect(annotationCommands(library.annotations, at: span("one")) == [.mark(.highlight), .mark(.strikethrough)])
    library = try library.applying(.unmark(.highlight, span("another")))
    #expect(library.annotations.isEmpty)
}

@Test func aNoteOutlivesItsRemovedHighlight() throws {
    var library = LibrarySnapshot()
    library = try library.applying(.mark(.highlight, span("one phrase")))
    library = try library.applying(.note("a thought", span("one phrase")))
    #expect(library.annotations.count == 1)
    library = try library.applying(.unmark(.highlight, span("one phrase")))
    #expect(library.annotations.map(\.note) == ["a thought"])
    #expect(library.annotations[0].mark == nil)
    library = try library.applying(.note("", span("one phrase")))
    #expect(library.annotations.isEmpty)
}

@Test func noteOnlyAnnotationRoundTripsWithNilMark() throws {
    let note = Annotation(materialID: "article:1", piece: 0, quote: "", note: "my note")
    let decoded = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(note))
    #expect(decoded == note)
}

@Test func albumsHoldAnItemInEveryAlbumItWasAddedTo() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    library.importBook(namedBook, at: .now)
    #expect(library.unsortedItems.map(\.id) == [namedBook.id])
    library = try library.applying(.addToAlbum("Web", itemIDs: [article.material.id]))
    library = try library.applying(.addToAlbum("Reading", itemIDs: [namedBook.id]))
    #expect(library.unsortedItems.isEmpty)
    #expect(library.items(inAlbum: "Inbox").map(\.id) == [article.material.id])
    #expect(library.items(inAlbum: "Web").map(\.id) == [article.material.id])
    library = try library.applying(.renameAlbum("Inbox", to: "Papers"))
    #expect(library.items(inAlbum: "Papers").map(\.id) == [article.material.id])
    #expect(throws: LibraryError.albumNameTaken("Web")) {
        try library.applying(.renameAlbum("Papers", to: "Web"))
    }
    library = try library.applying(.deleteAlbum("Reading"))
    #expect(library.unsortedItems.map(\.id) == [namedBook.id])
    library = try library.applying(.removeFromAlbum("Web", itemID: article.material.id))
    #expect(library.albumSummaries.map(\.count) == [1, 0])
}

@Test func readThroughKeepsEarlierParagraphsRead() {
    let progress = ReadingProgress().applying(.readThrough(piece: 5, itemID: "a"))
    #expect(progress.isPieceRead(5, of: "a", current: 0))
    #expect(!progress.isPieceRead(6, of: "a", current: 3))
    #expect(progress.isPieceRead(7, of: "a", current: 8))
}

@Test func deletingAnItemForgetsEverythingAboutIt() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    let progress = ReadingProgress().applying(.savePosition(.piece(3), itemID: article.material.id, progress: 0.5))
    let deleted = try library.applying(.delete(itemID: article.material.id))
    let forgotten = deleted.progressChanges(since: library).reduce(progress) { $0.applying($1) }
    #expect(deleted.articles.isEmpty && deleted.placements.isEmpty)
    #expect(forgotten == ReadingProgress())
}

@Test func readingProgressSavesWithoutRewritingTheCatalog() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory)
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    try await file.save(library)
    let written = try ["articles.json", "state.json"].map { name in
        try FileManager.default.attributesOfItem(atPath: directory.appending(path: name).path)[.modificationDate] as? Date
    }
    try await Task.sleep(for: .milliseconds(20))
    let moved = ReadingProgress().applying(.savePosition(.piece(1), itemID: article.material.id, progress: 0.1))
    try await file.saveProgress(moved)
    let after = try ["articles.json", "state.json"].map { name in
        try FileManager.default.attributesOfItem(atPath: directory.appending(path: name).path)[.modificationDate] as? Date
    }
    #expect(after == written)
    #expect(try await file.load().progress == moved)
}

@Test func aDownloadedVideoLeavesWithItsMaterial() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory)
    let download = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".mp4")
    try Data("mp4".utf8).write(to: download)
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    try await file.save(library)
    let stored = try await file.storeVideoFile(article.material.id, from: download, into: library)
    let saved = LibraryFile.videoFile(root: directory, name: try #require(stored.videoFiles[article.material.id]))
    #expect(FileManager.default.fileExists(atPath: saved.path))
    let deleted = try stored.applying(.delete(itemID: article.material.id))
    try await file.save(deleted, previous: stored)
    #expect(!FileManager.default.fileExists(atPath: saved.path))
}

@Test func stateWithInlinePackagesMovesThemToTheirOwnFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let inline = String(decoding: try JSONEncoder().encode([article]), as: UTF8.self)
    try Data(#"{"positions":{},"folders":["Inbox"],"placements":{"\#(article.material.id)":["Inbox"]},"packages":\#(inline)}"#.utf8)
        .write(to: directory.appending(path: "state.json"))
    let loaded = try await LibraryFile(url: directory).load().catalog
    #expect(loaded.articles.map(\.material.id) == [article.material.id])
    #expect(loaded.albums == ["Inbox"])
    #expect(FileManager.default.fileExists(atPath: directory.appending(path: "articles.json").path))
    let state = try String(contentsOf: directory.appending(path: "state.json"), encoding: .utf8)
    #expect(!state.contains("\"packages\""))
}

@Test func reimportKeepsMarksUntilTheBodyChanges() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    library.annotations.append(Annotation(materialID: article.material.id, piece: 0, quote: "Text", mark: .highlight))
    let first = library
    try library.importPackage(article, at: .now)
    #expect(library.annotations.count == 1)
    #expect(library.progressChanges(since: first).isEmpty)
    let changed = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, body: "A different page.")
    try library.importPackage(changed, at: .now)
    #expect(library.annotations.isEmpty)
    #expect(library.progressChanges(since: first) == [.restart(itemID: article.material.id)])
}

@Test func bookDirectoriesFollowTheBookIdentity() {
    let slash = BookRecord(metadata: bookMetadata(sourceName: "foo/bar.pdf"))
    let space = BookRecord(metadata: bookMetadata(sourceName: "foo bar.pdf"))
    #expect(slash.id != space.id)
    #expect(slash.directoryName != space.directoryName)
    #expect(!slash.directoryName.contains("/"))
    #expect(!space.directoryName.contains(" "))
}

@Test func failedArticleReplacementKeepsThePreviousFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory)
    let old = directory.appending(path: "old.tar")
    let new = directory.appending(path: "new.tar")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try writeDelivery(article, files: [("note.txt", Data("old".utf8))], to: old)
    let changed = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, body: "new")
    try writeDelivery(changed, files: [("note.txt", Data("new".utf8))], to: new)
    let stored = try await file.storeArticle(archive: old, into: LibrarySnapshot())
    let revision = try #require(stored.articleRevisions[article.material.id])
    let note = try #require(LibraryFile.articleFile(root: directory, materialID: article.material.id, path: "note.txt", revision: revision))
    try FileManager.default.removeItem(at: directory.appending(path: "state.json"))
    try FileManager.default.createDirectory(at: directory.appending(path: "state.json"), withIntermediateDirectories: true)
    await #expect(throws: (any Error).self) {
        try await file.storeArticle(archive: new, into: stored)
    }
    #expect(try String(contentsOf: note, encoding: .utf8) == "old")
}

@Test func failedBookReplacementKeepsThePreviousBook() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory)
    let original = directory.appending(path: "original")
    try makeBook(at: original, sourceName: "notes.pdf", content: "old")
    let stored = try await file.storeBook(try BookCatalog.inspect(from: original).record, from: original, into: LibrarySnapshot())
    let content = directory.appending(path: "books").appending(path: stored.books[0].directoryName).appending(path: "content.md")
    try FileManager.default.removeItem(at: directory.appending(path: "state.json"))
    try FileManager.default.createDirectory(at: directory.appending(path: "state.json"), withIntermediateDirectories: true)
    let replacement = directory.appending(path: "replacement")
    try makeBook(at: replacement, sourceName: "notes.pdf", content: "new")
    await #expect(throws: (any Error).self) {
        try await file.storeBook(try BookCatalog.inspect(from: replacement).record, from: replacement, into: stored)
    }
    #expect(try String(contentsOf: content, encoding: .utf8) == "old")
}

@Test func oneCorruptPackageDoesNotHideTheOthers() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let packages = directory.appending(path: "packages")
    try FileManager.default.createDirectory(at: packages, withIntermediateDirectories: true)
    try JSONEncoder().encode(article).write(to: packages.appending(path: "good.json"))
    try Data("not json".utf8).write(to: packages.appending(path: "bad.json"))
    try Data(#"{"positions":{},"notes":[],"folders":[]}"#.utf8).write(to: directory.appending(path: "state.json"))
    let file = LibraryFile(url: directory)
    let loaded = try await file.load().catalog
    #expect(loaded.articles.map(\.material.id) == [article.material.id])
    #expect(await file.corruptPackageNames == ["bad.json"])
}

@Test func legacyArticleAssetsSurviveLoad() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = LibraryFile(url: directory)
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    try await file.save(library)
    let picture = try #require(LibraryFile.articleFile(root: directory, materialID: article.material.id, path: "assets/pic.txt"))
    try FileManager.default.createDirectory(at: picture.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("pic".utf8).write(to: picture)
    _ = try await file.load()
    #expect(try String(contentsOf: picture, encoding: .utf8) == "pic")
}

@Test func cleartextServiceStaysOnThisDevice() {
    #expect(CaptureRoute.acceptsService(URL(string: "https://example.com")!))
    #expect(CaptureRoute.acceptsService(URL(string: "http://127.0.0.1:8787")!))
    #expect(!CaptureRoute.acceptsService(URL(string: "http://192.168.1.20:8787")!))
    #expect(!CaptureRoute.acceptsService(URL(string: "http://example.com")!))
}

private func bookMetadata(sourceName: String) -> BookMetadata {
    BookMetadata(
        title: "Notes",
        subtitle: nil,
        authors: ["Ada"],
        contributors: nil,
        language: "en",
        sourceName: sourceName,
        schemaVersion: 1,
        contentFile: "content.md",
        assetsDirectory: "assets",
        toc: []
    )
}

private func makeBook(at directory: URL, sourceName: String, content: String) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let metadata: [String: Any] = [
        "title": "Notes",
        "authors": ["Ada"],
        "language": "en",
        "source_name": sourceName,
        "schema_version": 1,
        "content_file": "content.md",
        "assets_directory": "assets",
        "toc": []
    ]
    try JSONSerialization.data(withJSONObject: metadata).write(to: directory.appending(path: "metadata.json"))
    try Data(#"{"headings":0,"images":0,"errors":[]}"#.utf8).write(to: directory.appending(path: "validation.json"))
    try Data(content.utf8).write(to: directory.appending(path: "content.md"))
}
