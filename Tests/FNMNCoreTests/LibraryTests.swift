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

@Test func theFNMNFolderKeepsSourceOnlySitesAndPreparedMaterials() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let folder = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: folder.appending(path: "deliveries"), withIntermediateDirectories: true)
    let catalog = #"{"collections":[{"id":"reading","name":"Reading"}],"sources":[{"name":"Example","url":"https://example.com","kind":"site","saved_in":["reading"],"found_in":["reading"],"materials":[]},{"name":"Author","url":"https://example.org","kind":"author","saved_in":["reading"],"found_in":["reading"],"materials":[{"title":"A","url":"https://example.com/a","saved_in":["reading"],"found_in":["reading"]}]}]}"#
    try Data(catalog.utf8).write(to: folder.appending(path: "catalog.json"))
    let delivery = folder.appending(path: "deliveries/a.tar")
    try writeDelivery(article, files: [("assets/p.png", Data("png".utf8))], to: delivery)

    let file = await libraryFile(root)
    let catalogued = try await file.applyBrowserCatalog(from: folder, into: LibrarySnapshot())
    let imported = try await file.addCloudDelivery(delivery, into: catalogued)
    try await file.save(imported, previous: LibrarySnapshot())
    #expect(imported.browserCatalog?.sources.first?.materials.isEmpty == true)
    #expect(imported.browserCatalog?.sources.last?.materials.first?.savedURLs == [])
    #expect(imported.articles.map(\.material.id) == [article.material.id])
    let reloaded = try await file.load()
    #expect(reloaded.catalog.browserCatalog == imported.browserCatalog)
    let entry = try #require(imported.articles.first)
    #expect(try await file.openCloudArticle(entry) == article)
    #expect(try Data(contentsOf: file.cachedFolder(of: entry).appending(path: "assets/p.png")) == Data("png".utf8))
}

@Test func aCatalogThatIsNotOnTheDeviceYetSaysItIsSyncing() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let folder = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = await libraryFile(root)
    do {
        _ = try await file.applyBrowserCatalog(from: folder, into: LibrarySnapshot())
        Issue.record("a missing catalog read as syncing")
    } catch let error as LibraryError {
        #expect(error == .catalogSyncing)
    }
}

@Test func anEvictedFileErrorCountsItsFilesAndNamesTheOneItKnows() {
    #expect(CloudFolderError.notDownloaded(count: 1).localizedDescription.hasPrefix("1 file is"))
    #expect(CloudFolderError.notDownloaded(count: 3).localizedDescription.hasPrefix("3 files are"))
    let named = CloudFolderError.notDownloaded(count: 1, name: "Quantum Kernels").localizedDescription
    #expect(named.contains("Quantum Kernels"))
}

func libraryFile(_ root: URL) async -> LibraryFile {
    let file = LibraryFile(url: root.appending(path: "library"), cache: root.appending(path: "cache"))
    await file.useCloudFolder(root.appending(path: "FNMN"))
    return file
}

private let paperLink = ImportPackage(
    material: Material(id: "link:https://dl.acm.org/doi/1", kind: .link, title: "dl.acm.org/doi/1", sourceURL: URL(string: "https://dl.acm.org/doi/1")!),
    sections: [], blocks: [], folders: ["HCI"]
)

@Test func aLinkTheServerCouldNotPrepareIsADeliveryInItsAlbum() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let delivery = root.appending(path: "link.tar")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try writeDelivery(paperLink, to: delivery)
    let imported = try await libraryFile(root).storeArticle(archive: delivery, into: LibrarySnapshot())
    let item = try #require(LibraryQueries(imported).items(inAlbum: "HCI").first)
    #expect(item.id == paperLink.material.id)
    #expect(item.kind == .link)
    #expect(item.originalURL == paperLink.material.sourceURL)
    #expect(item.excerpt == "dl.acm.org")
}

@Test func aMaterialMadeFromALinkedPageTakesTheLinksPlace() throws {
    var library = LibrarySnapshot()
    try library.importPackage(paperLink, at: .distantPast)
    library = try library.applying(.setArchived(true, itemID: paperLink.material.id))
    let paper = ImportPackage(
        material: Material(id: "article:https://dl.acm.org/doi/1", kind: .article, title: "Paper", sourceURL: paperLink.material.sourceURL!),
        sections: article.sections, blocks: article.blocks, folders: []
    )
    try library.importPackage(paper, at: .now)
    #expect(library.articles.map(\.material.id) == [paper.material.id])
    #expect(library.albums(of: paper.material.id) == ["HCI"])
    #expect(library.isArchived(paper.material.id))
    let queries = LibraryQueries(library)
    #expect(queries.archivedItems.first?.addedAt == .distantPast)

    try library.importPackage(paperLink, at: .now)
    #expect(library.articles.map(\.material.id) == [paper.material.id])
}

@Test func aPageIsShownByItsMaterialOnceOneIsMadeAndByItsLinkBefore() throws {
    let page = try #require(paperLink.material.sourceURL)
    var library = LibrarySnapshot()
    #expect(library.materialID(forPage: page) == nil)
    try library.importPackage(paperLink, at: .now)
    #expect(library.materialID(forPage: page) == paperLink.material.id)
    let paper = ImportPackage(
        material: Material(id: "article:https://dl.acm.org/doi/1", kind: .article, title: "Paper", sourceURL: page),
        sections: article.sections, blocks: article.blocks, folders: []
    )
    try library.importPackage(paper, at: .now)
    try library.importPackage(paperLink, at: .now)
    #expect(library.materialID(forPage: page) == paper.material.id)
}

@Test func importKeepsTheMarkdownBody() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = await libraryFile(root)
    let packaged = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, folders: article.folders, body: "A $x$ line.")
    let delivery = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".tar")
    try writeDelivery(packaged, to: delivery)
    var library = try await file.storeArticle(archive: delivery, into: LibrarySnapshot())
    library = try library.applying(.renameAlbum("Inbox", to: "Later"))
    #expect(try await file.openCloudArticle(try #require(library.articles.first)).body == "A $x$ line.")
    #expect(library.albums(of: article.material.id) == ["Later"])
}

@Test func whatAnOlderVersionKeptInTheAppMovesIntoTheFNMNFolder() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let appFolder = root.appending(path: "library")
    try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
    try JSONEncoder().encode([article]).write(to: appFolder.appending(path: "packages.json"))
    let file = await libraryFile(root)
    let loaded = try await file.load().catalog
    #expect(await file.holdsMaterialsInApp(loaded))
    let moved = try await file.moveIntoCloud(loaded)
    let entry = try #require(moved.articles.first)
    #expect(entry.delivery != nil)
    #expect(await !file.holdsMaterialsInApp(moved))
    #expect(!FileManager.default.fileExists(atPath: appFolder.appending(path: "articles").path))
    #expect(try await file.openCloudArticle(entry) == article)
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

@Test func aLinkedImageLeavesNoMarkupInTheExcerpt() {
    let body = "[![Rehaan Ahmad](assets/cover.png)](https://www.alphaxiv.org/@rehaan-ahmad)\n\nA long enough opening paragraph that becomes the excerpt of this article."
    #expect(ArticleBody.excerpt(body) == "A long enough opening paragraph that becomes the excerpt of this article.")
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
    #expect(loaded.catalog.annotations.contains { $0.id == UUID(uuidString: "00000000-0000-0000-0000-000000000009") && $0.note == "Remember this" && $0.piece == 4 && $0.marks.isEmpty })
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

@Test func aMaterialIsUnreadUntilSomethingHappensToIt() {
    #expect(ReadingProgress().status(of: article.material.id) == .unread)
}

@Test func openingSavingAPlaceOrMarkingReadThroughCountsAsStarted() {
    let opened = ReadingProgress().applying(.open(itemID: article.material.id), at: .now)
    #expect(opened.status(of: article.material.id) == .started)

    var placed = ReadingProgress()
    placed.positions[article.material.id] = ReadingPosition(blockID: "b1")
    #expect(placed.status(of: article.material.id) == .started)

    let marked = ReadingProgress().applying(.readThrough(piece: 2, itemID: article.material.id), at: .now)
    #expect(marked.status(of: article.material.id) == .started)
}

@Test func markingReadWinsOverEverythingElseTheMaterialHolds() {
    let progress = ReadingProgress()
        .applying(.open(itemID: article.material.id), at: .now)
        .applying(.readThrough(piece: 2, itemID: article.material.id), at: .now)
        .applying(.setRead(true, itemID: article.material.id), at: .now)
    #expect(progress.status(of: article.material.id) == .read)
}

@Test func aReadMaterialLeavesContinueAndTheDeepLinkAlike() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    try library.importPackage(laterArticle, at: .now)
    var progress = ReadingProgress()
        .applying(.open(itemID: article.material.id), at: Date(timeIntervalSinceReferenceDate: 1))
        .applying(.open(itemID: laterArticle.material.id), at: Date(timeIntervalSinceReferenceDate: 2))
        .applying(.setRead(true, itemID: laterArticle.material.id), at: Date(timeIntervalSinceReferenceDate: 3))
    #expect(LibraryQueries(library).continueItems(progress).map(\.id) == [article.material.id])
    #expect(library.continuedID(progress) == article.material.id)

    progress = progress.applying(.setRead(true, itemID: article.material.id), at: Date(timeIntervalSinceReferenceDate: 4))
    #expect(LibraryQueries(library).continueItems(progress).isEmpty)
    #expect(library.continuedID(progress) == nil)
}

@Test func anArchivedMaterialIsNotTheOneContinueOpens() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    var progress = ReadingProgress()
    progress.positions[article.material.id] = ReadingPosition(blockID: "b1")
    #expect(library.continuedID(progress) == article.material.id)

    library.archived = [article.material.id]
    #expect(library.continuedID(progress) == nil)
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

@Test func aFileKeptWithoutTheServerIsKnownByItsBytesLikeOneTheServerMade() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let slides = directory.appending(path: "slides.key")
    try Data("keynote".utf8).write(to: slides)
    let package = try ImportPackage.file(slides)
    #expect(package.material.id == "file:cae9d3b20ba8a78238099f47745d060f9be0f3812b9711d6ff27ce0f134a38fa")
    #expect(package.material.kind == .link)
    #expect(package.material.title == "slides")
    let library = try await libraryFile(directory).storeMade(package, into: LibrarySnapshot())
    let queries = LibraryQueries(library)
    #expect(queries.item(package.material.id)?.kind == .link)
}

@Test func aLinkKeptWithoutTheServerHasTheIDTheServerGivesIt() {
    let link = ImportPackage.link(URL(string: "https://dl.acm.org/doi/1/")!)
    #expect(link.material.id == "link:https://dl.acm.org/doi/1/")
    #expect(link.material.title == "dl.acm.org/doi/1")
}

@Test func aLinkKeptAsItIsBecomesADeliveryInItsOwnRight() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let url = try #require(URL(string: "https://dl.acm.org/doi/1"))
    let library = try await libraryFile(root).storeMade(.link(url), into: LibrarySnapshot())
    let queries = LibraryQueries(library)
    let item = try #require(queries.unsortedItems.first)
    #expect(item.id == "link:https://dl.acm.org/doi/1")
    #expect(item.kind == .link)
    #expect(item.originalURL == url)
    let entry = try #require(library.articles.first)
    #expect(entry.delivery != nil)
    #expect(try await libraryFile(root).load().catalog == library)
}

@Test func aMaterialMadeFromAFileHasItsAuthorsForASource() throws {
    var library = LibrarySnapshot()
    try library.importPackage(namedBook, at: .now)
    let queries = LibraryQueries(library)
    let item = try #require(queries.item(namedBook.material.id))
    #expect(item.kind == .book)
    #expect(item.source?.name == "Daniel A. Roberts")
    #expect(item.originalURL == nil)
    #expect(library.source(of: item.id)?.name == "Daniel A. Roberts")
}

private func page(_ address: String, source: PageSource? = nil) -> ImportPackage {
    ImportPackage(
        material: Material(id: "article:\(address)", kind: .article, title: address, sourceURL: URL(string: address)!, source: source),
        sections: [],
        blocks: [Block(id: "b1", sectionID: nil, kind: .paragraph, html: "<p>Text</p>")]
    )
}

private func blog(_ name: String?, _ address: String) -> PageSource {
    PageSource(name: name, homepage: URL(string: address)!)
}

@Test func aLinkAddedLaterJoinsTheBlogTheBrowserCatalogNames() throws {
    var library = LibrarySnapshot()
    let catalog = #"{"collections":[],"sources":[{"name":"Hugh Zhang · Blog","url":"https://hughbzhang.com/blog/","kind":"blog","saved_in":[],"found_in":[],"materials":[{"title":"A","url":"https://hughbzhang.com/blog/a.html","saved_in":[],"found_in":[]}]}]}"#
    library.browserCatalog = try JSONDecoder().decode(BrowserCatalog.self, from: Data(catalog.utf8))
    try library.importPackage(page("https://hughbzhang.com/blog/a.html"), at: .now)
    try library.importPackage(page("https://www.hughbzhang.com/blog/b.html", source: blog(nil, "https://hughbzhang.com/")), at: .now)
    try library.importPackage(page("https://hughbzhang.com/about"), at: .now)
    let queries = LibraryQueries(library)
    let names = Dictionary(uniqueKeysWithValues: queries.items.map { ($0.originalURL!.path, $0.source?.name) })
    #expect(names["/blog/a.html"] == "Hugh Zhang · Blog")
    #expect(names["/blog/b.html"] == "Hugh Zhang · Blog")
    #expect(names["/about"] == "hughbzhang")
}

@Test func articlesOfOneBlogShareThePublisherTheServerFoundForAnyOfThem() throws {
    var library = LibrarySnapshot()
    let zhang = blog("Alex L. Zhang", "https://alexzhang13.github.io/blog/")
    try library.importPackage(page("https://alexzhang13.github.io/blog/2026/shape/", source: zhang), at: .now)
    try library.importPackage(page("https://alexzhang13.github.io/blog/2025/older/"), at: .now)
    try library.importPackage(page("https://alexzhang13.github.io/projects/rlm/"), at: .now)
    let queries = LibraryQueries(library)
    let shape = try #require(queries.item("article:https://alexzhang13.github.io/blog/2026/shape/")?.source)
    #expect(shape.name == "Alex L. Zhang")
    #expect(shape.homepage == zhang.homepage)
    #expect(queries.items(fromSource: shape.id).count == 2)
    let older = try #require(queries.item("article:https://alexzhang13.github.io/blog/2025/older/")?.source)
    #expect(older == shape)
    #expect(library.source(of: "article:https://alexzhang13.github.io/blog/2025/older/") == shape)
    #expect(queries.item("article:https://alexzhang13.github.io/projects/rlm/")?.source?.name == "alexzhang13")
}

@Test func publishersThatCallThemselvesTheSameAreToldApartByTheirPage() throws {
    var library = LibrarySnapshot()
    try library.importPackage(page("https://medium.com/@ann/one", source: blog("Medium", "https://medium.com/@ann/")), at: .now)
    try library.importPackage(page("https://medium.com/@bob/two", source: blog("Medium", "https://medium.com/@bob/")), at: .now)
    let queries = LibraryQueries(library)
    let ann = try #require(queries.item("article:https://medium.com/@ann/one")?.source)
    let bob = try #require(queries.item("article:https://medium.com/@bob/two")?.source)
    #expect(ann.name == bob.name)
    #expect(ann.id != bob.id)
    #expect(queries.items(fromSource: ann.id).map(\.id) == ["article:https://medium.com/@ann/one"])
}

@Test func aPublisherWithoutAFoundNameIsNamedAfterItsSite() throws {
    var library = LibrarySnapshot()
    try library.importPackage(page("https://alexzhang13.github.io/blog/2026/shape/", source: blog(nil, "https://alexzhang13.github.io/blog/")), at: .now)
    let queries = LibraryQueries(library)
    let source = try #require(queries.items.first?.source)
    #expect(source.name == "alexzhang13")
    #expect(source.homepage == URL(string: "https://alexzhang13.github.io/blog/"))
}

@Test func aLinkToAHeadingNamesTheSameMaterialAsTheLinkToThePage() throws {
    var library = LibrarySnapshot()
    try library.importPackage(page("https://huggingface.co/spaces/t-tech/manifolds"), at: .now)
    let heading = try #require(URL(string: "https://huggingface.co/spaces/t-tech/manifolds#what-we-reproduced"))
    #expect(library.materialID(forPage: heading) == "article:https://huggingface.co/spaces/t-tech/manifolds")
    #expect(heading.withoutFragment.absoluteString == "https://huggingface.co/spaces/t-tech/manifolds")
    #expect(URL(string: "https://example.com/a?x=1")!.withoutFragment.absoluteString == "https://example.com/a?x=1")
}

@Test func aPackageWithoutAPublisherStillDecodes() throws {
    let bare = #"{"version":1,"material":{"id":"a","kind":"article","title":"T","sourceURL":"https://example.com/a"},"sections":[],"blocks":[],"folders":[]}"#
    #expect(try JSONDecoder().decode(ImportPackage.self, from: Data(bare.utf8)).material.source == nil)
    let named = #"{"version":1,"material":{"id":"a","kind":"article","title":"T","sourceURL":"https://example.com/a","source":{"name":"Example","homepage":"https://example.com/blog/"}},"sections":[],"blocks":[],"folders":[]}"#
    #expect(try JSONDecoder().decode(ImportPackage.self, from: Data(named.utf8)).material.source == blog("Example", "https://example.com/blog/"))
}

@Test func stateThatStillListsBooksLoads() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(#"{"books":[{"id":"book:a.pdf"}],"albums":["Later"]}"#.utf8)
        .write(to: directory.appending(path: "state.json"))
    let snapshot = try await LibraryFile(url: directory).load().catalog
    #expect(snapshot.albums == ["Later"])
}

private let namedArticle = ImportPackage(
    material: Material(id: "article:https://example.com/search", kind: .article, title: "Kernel Methods", sourceURL: URL(string: "https://example.com/search")!, byline: "Alice"),
    sections: [Section(id: "s1", parentID: nil, title: "NTK", level: 1, firstBlockID: "b1")],
    blocks: [Block(id: "b1", sectionID: "s1", kind: .paragraph, html: "<p>hidden body text</p>")],
    folders: ["Papers"]
)

private let namedBook = ImportPackage(
    material: Material(
        id: "book:principles-of-deep-learning-theory.pdf",
        kind: .book,
        title: "The Principles of Deep Learning Theory",
        sourceURL: nil,
        byline: "Daniel A. Roberts"
    ),
    sections: [],
    blocks: [],
    body: "# Effective Theory\n\nThe book's first paragraph."
)

@Test func librarySearchMatchesCatalogFieldsAndIgnoresBody() throws {
    var library = LibrarySnapshot()
    try library.importPackage(namedArticle, at: .now)
    try library.importPackage(namedBook, at: .now)
    var queries = LibraryQueries(library)
    func ids(_ query: String) -> Set<String> {
        Set(queries.items(matching: query).map(\.id))
    }
    #expect(ids(" ") == [namedArticle.material.id, namedBook.material.id])
    #expect(ids("kernel") == [namedArticle.material.id])
    #expect(ids("Alice") == [namedArticle.material.id])
    #expect(ids("Papers") == [namedArticle.material.id])
    #expect(ids("NTK") == [namedArticle.material.id])
    #expect(ids("roberts") == [namedBook.material.id])
    #expect(ids("Effective Theory") == [namedBook.material.id])
    #expect(ids("hidden body text").isEmpty)
    #expect(ids("xyzzy").isEmpty)
    let headed = ImportPackage(
        material: Material(id: "article:headed", kind: .article, title: "Plain", sourceURL: URL(string: "https://example.com/headed")!),
        sections: [],
        blocks: [],
        body: "# Kernel Trick\n\nhidden body text"
    )
    try library.importPackage(headed, at: .now)
    queries = LibraryQueries(library)
    #expect(ids("Kernel Trick") == ["article:headed"])
    #expect(ids("hidden body text").isEmpty)
    let accented = ImportPackage(
        material: Material(id: "article:accented", kind: .article, title: "Café Baseline", sourceURL: URL(string: "https://example.com/accented")!),
        sections: [],
        blocks: [],
        body: "plain body text"
    )
    try library.importPackage(accented, at: .now)
    queries = LibraryQueries(library)
    #expect(ids("cafe") == ["article:accented"])
    #expect(ids("CAFÉ") == ["article:accented"])
    let book = queries.items.filter { $0.id == namedBook.material.id }
    #expect(queries.search("kernel", in: book).isEmpty)
    #expect(queries.search("roberts", in: book).map(\.id) == [namedBook.material.id])
}

@Test func annotationSearchKeepsAFoundMaterialWholeAndElsewhereOnlyMatchingAnnotations() throws {
    var library = LibrarySnapshot()
    try library.importPackage(namedArticle, at: .now)
    try library.importPackage(namedBook, at: .now)
    let article = namedArticle.material.id, book = namedBook.material.id
    library = try library.applying(.mark(.highlight, AnnotationTarget(materialID: article, piece: 0, text: "first quote")))
    library = try library.applying(.mark(.highlight, AnnotationTarget(materialID: article, piece: 1, text: "second quote")))
    library = try library.applying(.mark(.highlight, AnnotationTarget(materialID: book, piece: 0, text: "an effective quote")))
    library = try library.applying(.note("worth a Kernel look", AnnotationTarget(materialID: book, piece: 1, text: "plain")))
    func found(_ query: String) -> [String: Int] {
        let queries = LibraryQueries(library)
        return Dictionary(uniqueKeysWithValues: queries.annotationGroups(matching: query).map { ($0.id, $0.annotations.count) })
    }
    #expect(found("") == [article: 2, book: 2])
    #expect(found("kernel") == [article: 2, book: 1])
    #expect(found("second") == [article: 1])
    #expect(found("xyzzy").isEmpty)
}

@Test func aParagraphHoldsEveryMarkAndItsNoteInOneRecord() throws {
    var library = LibrarySnapshot()
    library = try library.applying(.mark(.highlight, span("one phrase")))
    library = try library.applying(.mark(.highlight, span("end here")))
    library = try library.applying(.mark(.strikethrough, span("another")))
    library = try library.applying(.note("  a thought ", paragraph))
    let record = try #require(library.annotations.first)
    #expect(library.annotations.count == 1)
    #expect(record.text == paragraph.text)
    #expect(record.marks == [
        QuoteMark(quote: "one phrase", mark: .highlight),
        QuoteMark(quote: "end here", mark: .highlight),
        QuoteMark(quote: "another", mark: .strikethrough),
    ])
    #expect(record.note == "a thought")
}

@Test func theExcerptOpensAtTheFirstMarkOfALongParagraph() {
    let words = (0..<80).map { "word\($0)" }.joined(separator: " ")
    let record = Annotation(materialID: "article:1", piece: 0, text: words, marks: [QuoteMark(quote: "word60 word61", mark: .highlight)])
    let excerpt = record.excerpt(limit: 100)
    #expect(excerpt.text.hasPrefix("…") && excerpt.text.hasSuffix("…") && excerpt.text.count <= 104)
    let run = excerpt.runs[0]
    #expect((excerpt.text as NSString).substring(with: run.range) == "word60 word61")
    let short = Annotation(materialID: "article:1", piece: 0, text: " one two ", marks: [QuoteMark(quote: "two", mark: .strikethrough)])
    #expect(short.excerpt().text == "one two")
    #expect((short.excerpt().text as NSString).substring(with: short.excerpt().runs[0].range) == "two")
}

@Test func filesFromBeforeParagraphRecordsMergeIntoOneRecordPerParagraph() throws {
    let material = "article:1"
    let paragraphText = "one phrase and another phrase end here"
    let json = """
    [{"id":"00000000-0000-0000-0000-000000000001","materialID":"\(material)","piece":2,"quote":"one phrase","mark":"highlight","updatedAt":1000},
     {"id":"00000000-0000-0000-0000-000000000002","materialID":"\(material)","piece":2,"quote":"\(paragraphText)","note":"kept","mark":null},
     {"id":"00000000-0000-0000-0000-000000000003","materialID":"\(material)","piece":3,"quote":"old quote","caption":"from a caption","mark":null},
     {"id":"00000000-0000-0000-0000-000000000004","materialID":"\(material)","piece":7,"quote":"second","mark":"highlight","updatedAt":1000.5},
     {"id":"00000000-0000-0000-0000-000000000005","materialID":"\(material)","piece":8,"quote":"third","mark":"highlight","updatedAt":1001}]
    """
    let records = try JSONDecoder().decode(StoredAnnotations.self, from: Data(json.utf8)).records
    #expect(records.map(\.piece) == [2, 3, 7, 8])
    #expect(records[0].text == paragraphText)
    #expect(records[0].marks == [QuoteMark(quote: "one phrase", mark: .highlight)])
    #expect(records[0].note == "kept")
    #expect(records[1].marks.isEmpty && records[1].note == "from a caption")
    #expect(records[2].marks == [QuoteMark(quote: "second", mark: .highlight)])
    let current = try JSONEncoder().encode(records)
    #expect(try JSONDecoder().decode(StoredAnnotations.self, from: current).records == records)
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
    let data = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","materialID":"article:1","piece":2,"quote":"old quote","caption":"kept"}]"#.utf8)
    let annotation = try #require(JSONDecoder().decode(StoredAnnotations.self, from: data).records.first)
    #expect(annotation.marks == [QuoteMark(quote: "old quote", mark: .highlight)])
    #expect(annotation.text == "old quote")
    #expect(annotation.note == "kept")
}

private let paragraph = AnnotationTarget(materialID: "article:1", piece: 2, text: "one phrase and another phrase end here")

private func span(_ quote: String) -> AnnotationTarget {
    let range = (paragraph.text as NSString).range(of: quote)
    return AnnotationTarget(materialID: paragraph.materialID, piece: paragraph.piece, text: paragraph.text, span: TextSpan(start: range.location, length: range.length))
}

@Test func touchingHighlightsBecomeOneRun() throws {
    var library = LibrarySnapshot()
    library = try library.applying(.mark(.highlight, span("one phrase")))
    library = try library.applying(.mark(.highlight, span("phrase and another")))
    #expect(library.annotations.flatMap(\.marks).map(\.quote) == ["one phrase and another"])
    library = try library.applying(.mark(.strikethrough, span("end")))
    #expect(library.annotations.count == 1)
    #expect(library.annotations[0].marks.count == 2)
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
    #expect(library.annotations[0].marks.isEmpty)
    library = try library.applying(.note("", span("one phrase")))
    #expect(library.annotations.isEmpty)
}

@Test func noteOnlyAnnotationRoundTripsWithoutMarks() throws {
    let note = Annotation(materialID: "article:1", piece: 0, text: "", note: "my note")
    let decoded = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(note))
    #expect(decoded == note)
}

@Test func albumsHoldAnItemInEveryAlbumItWasAddedTo() throws {
    var library = LibrarySnapshot()
    try library.importPackage(article, at: .now)
    try library.importPackage(namedBook, at: .now)
    var queries = LibraryQueries(library)
    #expect(queries.unsortedItems.map(\.id) == [namedBook.material.id])
    library = try library.applying(.addToAlbum("Web", itemIDs: [article.material.id]))
    queries = LibraryQueries(library)
    library = try library.applying(.addToAlbum("Reading", itemIDs: [namedBook.material.id]))
    queries = LibraryQueries(library)
    #expect(queries.unsortedItems.isEmpty)
    #expect(queries.items(inAlbum: "Inbox").map(\.id) == [article.material.id])
    #expect(queries.items(inAlbum: "Web").map(\.id) == [article.material.id])
    library = try library.applying(.renameAlbum("Inbox", to: "Papers"))
    queries = LibraryQueries(library)
    #expect(queries.items(inAlbum: "Papers").map(\.id) == [article.material.id])
    #expect(throws: LibraryError.albumNameTaken("Web")) {
        try library.applying(.renameAlbum("Papers", to: "Web"))
    }
    library = try library.applying(.deleteAlbum("Reading"))
    queries = LibraryQueries(library)
    #expect(queries.unsortedItems.map(\.id) == [namedBook.material.id])
    library = try library.applying(.removeFromAlbum("Web", itemID: article.material.id))
    queries = LibraryQueries(library)
    #expect(queries.albumSummaries.map(\.count) == [1, 0])
}

@Test func readThroughKeepsEarlierParagraphsRead() {
    let progress = ReadingProgress().applying(.readThrough(piece: 5, itemID: "a"))
    #expect(progress.isPieceRead(5, of: "a", current: 0))
    #expect(!progress.isPieceRead(6, of: "a", current: 3))
    #expect(progress.isPieceRead(7, of: "a", current: 8))
}

@Test func hidingTheReadingLineKeepsTheBlocksAboveItRead() {
    let progress = ReadingProgress().applying(.line(ReadingLine(piece: 4, fraction: 0.5), itemID: "a"))
    #expect(progress.isPieceRead(3, of: "a", current: 0))
    #expect(!progress.isPieceRead(4, of: "a", current: 0))
}

@Test func aMaterialOpensAtItsFirstUnreadBlock() {
    let marked = ReadingProgress().applying(.readThrough(piece: 5, itemID: "a"))
    #expect(ReadingProgress().openingPiece(of: "a", place: nil, count: 10) == nil)
    #expect(ReadingProgress().openingPiece(of: "a", place: 3, count: 10) == 3)
    #expect(marked.openingPiece(of: "a", place: 2, count: 10) == 6)
    #expect(marked.openingPiece(of: "a", place: nil, count: 10) == 6)
    #expect(marked.openingPiece(of: "a", place: 8, count: 10) == 8)
    #expect(marked.openingPiece(of: "a", place: 2, count: 6) == 5)
    #expect(marked.applying(.setRead(true, itemID: "a")).openingPiece(of: "a", place: 2, count: 10) == 2)
}

@Test func theReadingLineStopsBetweenLinesOfTextAndNeverInsideOne() {
    let lines = ReadingLine.merged([0...20, 20...40, 60...80, 61...79, 100...140, 110...125, 140...140, 400...420])
    #expect(lines == [0...20, 20...40, 60...80, 100...140, 400...420])
    let stops = ReadingLine.stops(within: -16...436, lines: lines)
    #expect(stops == [20...20, 50...50, 90...90, 148...392])
    #expect(ReadingLine.nearest(to: 33, in: stops) == 20)
    #expect(ReadingLine.nearest(to: 250, in: stops) == 250)
    #expect(ReadingLine.nearest(to: 143, in: stops) == 148)
    #expect(ReadingLine.nearest(to: 33, in: []) == nil)
    #expect(ReadingLine.stops(within: 0...300, lines: [200...220, 240...260]) == [8...192, 230...230])
    #expect(ReadingLine.stops(within: 0...300, lines: []) == [8...292])
    #expect(ReadingLine.stops(within: 0...40, lines: []) == [])
}

@Test func withTheReadingLineTheBlocksAboveItAndItsOwnBlockDownToItAreRead() {
    let progress = ReadingProgress().applying(.readThrough(piece: 8, itemID: "a"))
    let line = ReadingLine(piece: 3, fraction: 0.5)
    #expect(progress.readShare(of: 2, in: "a", line: line) == 1)
    #expect(progress.readShare(of: 3, in: "a", line: line) == 0.5)
    #expect(progress.readShare(of: 5, in: "a", line: line) == 0)
    #expect(progress.applying(.setRead(true, itemID: "a")).readShare(of: 5, in: "a", line: ReadingLine(piece: 3, fraction: 0)) == 1)
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

@Test func aVideoAnOlderVersionSavedInTheAppBecomesTheOriginalBesideItsDelivery() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let app = directory.appending(path: "library")
    try FileManager.default.createDirectory(at: app.appending(path: "videos"), withIntermediateDirectories: true)
    try Data("mp4".utf8).write(to: app.appending(path: "videos/a.mp4"))
    try Data(#"{"videoFiles":{"\#(article.material.id)":"a.mp4"}}"#.utf8).write(to: app.appending(path: "state.json"))
    let file = await libraryFile(directory)
    _ = try await file.load()
    let delivery = directory.appending(path: "a.tar")
    try writeDelivery(article, to: delivery)
    let library = try await file.storeArticle(archive: delivery, into: LibrarySnapshot())
    #expect(await file.holdsMaterialsInApp(library))
    _ = try await file.moveIntoCloud(library)
    let entry = try #require(library.articles.first)
    let original = directory.appending(path: "FNMN/originals").appending(path: try #require(entry.originalName(pathExtension: "mp4")))
    #expect(try String(contentsOf: original, encoding: .utf8) == "mp4")
    #expect(entry.originalStem.map { "\($0).tar" } == entry.delivery)
    #expect(!FileManager.default.fileExists(atPath: app.appending(path: "videos").path))
    #expect(await !file.holdsMaterialsInApp(library))
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
    library.annotations.append(Annotation(materialID: article.material.id, piece: 0, text: "Text", marks: [QuoteMark(quote: "Text", mark: .highlight)]))
    let first = library
    try library.importPackage(article, at: .now)
    #expect(library.annotations.count == 1)
    #expect(library.progressChanges(since: first).isEmpty)
    let changed = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, body: "A different page.")
    try library.importPackage(changed, at: .now)
    #expect(library.annotations.isEmpty)
    #expect(library.progressChanges(since: first) == [.restart(itemID: article.material.id)])
}

@Test func aMarkFromAnotherDeviceOnTheNewTextOutlivesTheDeliveryArrivingAfterIt() throws {
    var library = LibrarySnapshot()
    let rewritten = Date(timeIntervalSince1970: 1_000)
    try library.importPackage(article, at: .now)
    library.annotations.append(Annotation(materialID: article.material.id, piece: 0, text: "Old", note: "before", updatedAt: rewritten - 60))
    library.annotations.append(Annotation(materialID: article.material.id, piece: 1, text: "New", note: "after", updatedAt: rewritten + 60))
    let changed = ImportPackage(material: article.material, sections: article.sections, blocks: article.blocks, body: "A different page.")
    try library.importPackage(changed, at: .now, delivery: "a.tar", deliveredAt: rewritten)
    #expect(library.annotations.map(\.note) == ["after"])
}

@Test func theOldPackagesFolderGoesOnceEveryPackageIsIn() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let packages = directory.appending(path: "packages")
    try FileManager.default.createDirectory(at: packages, withIntermediateDirectories: true)
    try JSONEncoder().encode(article).write(to: packages.appending(path: "good.json"))
    let loaded = try await LibraryFile(url: directory).load().catalog
    #expect(loaded.articles.map(\.material.id) == [article.material.id])
    #expect(!FileManager.default.fileExists(atPath: packages.path))
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
    #expect(FileManager.default.fileExists(atPath: packages.appending(path: "bad.json").path))
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

private func prepared(_ id: String, kind: Material.Kind = .article, source: String, at date: TimeInterval) throws -> (ImportPackage, Date) {
    let url = URL(string: "https://\(source).com/\(id)")!
    let material = Material(id: id, kind: kind, title: id, sourceURL: url, source: PageSource(name: source, homepage: URL(string: "https://\(source).com")!))
    let package = ImportPackage(
        material: material,
        sections: [Section(id: "s", parentID: nil, title: "S", level: 1, firstBlockID: "b")],
        blocks: [Block(id: "b", sectionID: "s", kind: .paragraph, html: "<p>\(id)</p>")],
        folders: []
    )
    return (package, Date(timeIntervalSince1970: date))
}

@Test func collectionsGatherTheSameMaterialsByPublisherTypeAndMonth() throws {
    var library = LibrarySnapshot()
    for (id, kind, source, date) in [("a", Material.Kind.article, "alpha", 1_000_000.0), ("b", .video, "alpha", 1_000_020), ("c", .article, "beta", 90_000_000)] {
        let (package, delivered) = try prepared(id, kind: kind, source: source, at: date)
        try library.importPackage(package, at: delivered)
    }
    let queries = LibraryQueries(library)
    let publishers = queries.groups(by: .publishers, sortedBy: .standard)
    #expect(publishers.map(\.name) == ["alpha", "beta"])
    #expect(publishers.map(\.count) == [2, 1])
    #expect(queries.groups(by: .publishers, sortedBy: .size).first?.name == "alpha")
    #expect(queries.groups(by: .types, sortedBy: .name).map(\.name) == ["Articles", "Videos"])
    #expect(queries.groups(by: .months, sortedBy: .standard).count == 2)
    let articles = queries.items(in: .types, key: "article")
    #expect(articles.map(\.id) == ["c", "a"])
}

@Test func recentlyOpenedPutsFirstWhatWasOpenedLastItselfOrThroughAMaterial() throws {
    var library = LibrarySnapshot()
    for (id, source, date) in [("a", "alpha", 1_000_000.0), ("b", "beta", 2_000_000), ("c", "gamma", 3_000_000)] {
        let (package, delivered) = try prepared(id, source: source, at: date)
        try library.importPackage(package, at: delivered)
    }
    let queries = LibraryQueries(library)
    let progress = ReadingProgress()
        .applying(.open(itemID: "a"), at: Date(timeIntervalSince1970: 10))
        .applying(.openGroup(id: AlbumSummary.id(.publishers, queries.item("b")!.source!.id)), at: Date(timeIntervalSince1970: 20))
    #expect(queries.groups(by: .publishers, sortedBy: .opened, progress: progress).map(\.name) == ["beta", "alpha", "gamma"])
    let opened = progress.readings.compactMapValues(\.openedAt)
    let arranged = LibraryQueries.arrange(queries.items, sortedBy: .opened, groupedBy: .none, opened: opened)
    #expect(arranged.first?.items.map(\.id) == ["a", "c", "b"])
}
