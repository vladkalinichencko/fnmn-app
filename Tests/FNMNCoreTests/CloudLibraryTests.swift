@testable import FNMNCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

private func png(side: Int = 8) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private let illustrated = ImportPackage(
    material: Material(id: "article:cloud", kind: .article, title: "Cloud", sourceURL: URL(string: "https://example.com/cloud")!),
    sections: [],
    blocks: [],
    body: "![c](assets/cover.png)\n\nA long enough opening paragraph so the article has an excerpt.\n\n![d](assets/diagram.png)"
)

@Test func aMaterialFromICloudKeepsOnlyItsCoverInTheAppAndUnpacksWhenOpened() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud.appending(path: "deliveries"), withIntermediateDirectories: true)
    let archive = cloud.appending(path: "deliveries/a.tar")
    try writeDelivery(illustrated, files: [("assets/cover.png", try png()), ("assets/diagram.png", try png())], to: archive)
    let file = LibraryFile(url: root.appending(path: "library"), cache: root.appending(path: "cache"))
    await file.useCloudFolder(cloud)

    var library = try await file.addCloudDelivery(archive, into: LibrarySnapshot())
    try await file.save(library, previous: LibrarySnapshot())
    let entry = try #require(library.articles.first)
    #expect(entry.delivery == "a.tar")
    #expect(entry.cover == .stored(materialID: "article:cloud"))
    #expect(FileManager.default.fileExists(atPath: LibraryFile.coverFile(root: file.root, materialID: "article:cloud").path))
    #expect(!FileManager.default.fileExists(atPath: file.root.appending(path: "articles").path))
    #expect(await !file.isUnpacked(entry))

    #expect(try await file.openCloudArticle(entry) == illustrated)
    #expect(await file.isUnpacked(entry))
    #expect(FileManager.default.fileExists(atPath: file.cachedFolder(of: entry).appending(path: "assets/diagram.png").path))

    let deleted = try library.applying(.delete(itemID: "article:cloud"))
    try await file.save(deleted, previous: library)
    library = deleted
    #expect(!FileManager.default.fileExists(atPath: file.cachedFolder(of: entry).path))
    #expect(!FileManager.default.fileExists(atPath: LibraryFile.coverFile(root: file.root, materialID: "article:cloud").path))
}

@Test func aMaterialTheServerPreparesForThePhoneJoinsTheFolderInICloud() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
    let download = root.appending(path: "download.tar")
    try writeDelivery(illustrated, files: [("assets/cover.png", try png())], to: download)
    let file = LibraryFile(url: root.appending(path: "library"), cache: root.appending(path: "cache"))
    await file.useCloudFolder(cloud)

    let library = try await file.storeArticle(archive: download, into: LibrarySnapshot())
    let entry = try #require(library.articles.first)
    let placed = try #require(await file.deliveryURL(of: entry))
    #expect(placed.deletingLastPathComponent().lastPathComponent == "deliveries")
    #expect(FileManager.default.fileExists(atPath: placed.path))
    #expect(FileManager.default.fileExists(atPath: download.path))
    #expect(try await file.openCloudArticle(entry) == illustrated)
}

private let page = ImportPackage.link(URL(string: "https://example.com/page")!)

private func twoDevices() async throws -> (phone: LibraryFile, pad: LibraryFile, deliveries: [URL], root: URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud.appending(path: "deliveries"), withIntermediateDirectories: true)
    let phone = LibraryFile(url: root.appending(path: "phone"), cache: root.appending(path: "phone-cache"))
    let pad = LibraryFile(url: root.appending(path: "pad"), cache: root.appending(path: "pad-cache"))
    await phone.useCloudFolder(cloud)
    await pad.useCloudFolder(cloud)
    let source = root.appending(path: "page.tar")
    try writeDelivery(page, to: source)
    _ = try await phone.storeArticle(archive: source, into: LibrarySnapshot())
    let deliveries = try FileManager.default.contentsOfDirectory(at: cloud.appending(path: "deliveries"), includingPropertiesForKeys: nil)
    return (phone, pad, deliveries, root)
}

@Test func anotherDevicesDeliveryIsTakenWhenNewOrRewrittenAndNotOnceDeleted() async throws {
    let (_, pad, deliveries, _) = try await twoDevices()
    let found = try await pad.changedDeliveries(deliveries, in: LibrarySnapshot())
    #expect(found.deliveries == deliveries)
    var library = try await pad.addCloudDelivery(deliveries[0], into: found.snapshot)
    #expect(try await pad.changedDeliveries(deliveries, in: library).deliveries.isEmpty)

    try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: deliveries[0].path)
    #expect(try await pad.changedDeliveries(deliveries, in: library).deliveries == deliveries)

    library = try library.applying(.delete(itemID: page.material.id), at: .now.addingTimeInterval(120))
    #expect(try await pad.changedDeliveries(deliveries, in: library).deliveries.isEmpty)
}

@Test func anOlderDuplicateDeliveryDoesNotComeBackButANewerOneDoes() async throws {
    let (_, pad, deliveries, root) = try await twoDevices()
    let cloud = root.appending(path: "FNMN/deliveries")
    var library = try await pad.addCloudDelivery(deliveries[0], into: LibrarySnapshot())
    let duplicate = cloud.appending(path: "duplicate.tar")
    try FileManager.default.copyItem(at: deliveries[0], to: duplicate)
    try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-86_400)], ofItemAtPath: duplicate.path)

    var all = try FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil)
    #expect(try await pad.changedDeliveries(all, in: library).deliveries.isEmpty)

    try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: duplicate.path)
    all = try FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil)
    let second = try await pad.changedDeliveries(all, in: library).deliveries
    #expect(second.map(\.lastPathComponent) == ["duplicate.tar"])
    library = try await pad.addCloudDelivery(second[0], into: library)
    all = try FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil)
    #expect(try await pad.changedDeliveries(all, in: library).deliveries.isEmpty)
}

private func writeLateIDDelivery(materialID: String, bodyBytes: Int, to url: URL) throws {
    let body = String(repeating: "x", count: bodyBytes)
    let json = "{\"body\":\"\(body)\",\"folders\":[],\"sections\":[],\"version\":1,\"material\":{\"id\":\"\(materialID)\",\"title\":\"Late\",\"kind\":\"article\"},\"blocks\":[]}"
    let content = Data(json.utf8)
    var bytes = [UInt8](repeating: 0, count: 512)
    for (index, byte) in "package.json".utf8.enumerated() {
        bytes[index] = byte
    }
    let size = String(repeating: "0", count: 11 - String(content.count, radix: 8).count) + String(content.count, radix: 8)
    for (index, byte) in size.utf8.enumerated() {
        bytes[124 + index] = byte
    }
    for (index, byte) in "0000644".utf8.enumerated() {
        bytes[100 + index] = byte
    }
    for index in 148..<156 {
        bytes[index] = UInt8(ascii: " ")
    }
    bytes[156] = UInt8(ascii: "0")
    for (index, byte) in "ustar".utf8.enumerated() {
        bytes[257 + index] = byte
    }
    for (index, byte) in "00".utf8.enumerated() {
        bytes[263 + index] = byte
    }
    let sum = bytes.reduce(0) { $0 + Int($1) }
    let checksum = String(repeating: "0", count: 6 - String(sum, radix: 8).count) + String(sum, radix: 8)
    for (index, byte) in checksum.utf8.enumerated() {
        bytes[148 + index] = byte
    }
    bytes[154] = 0
    bytes[155] = UInt8(ascii: " ")
    var archive = Data(bytes)
    archive.append(content)
    archive.append(Data(count: (512 - content.count % 512) % 512))
    archive.append(Data(count: 1024))
    try archive.write(to: url)
}

@Test func aStaleDuplicateWithALateMaterialIDIsSkipped() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud.appending(path: "deliveries"), withIntermediateDirectories: true)
    let phone = LibraryFile(url: root.appending(path: "phone"), cache: root.appending(path: "phone-cache"))
    let pad = LibraryFile(url: root.appending(path: "pad"), cache: root.appending(path: "pad-cache"))
    await phone.useCloudFolder(cloud)
    await pad.useCloudFolder(cloud)
    let source = root.appending(path: "late.tar")
    try writeLateIDDelivery(materialID: "article:late-id", bodyBytes: 40_000, to: source)
    _ = try await phone.storeArticle(archive: source, into: LibrarySnapshot())
    let folder = cloud.appending(path: "deliveries")
    let deliveries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    let library = try await pad.addCloudDelivery(deliveries[0], into: LibrarySnapshot())
    let duplicate = folder.appending(path: "duplicate.tar")
    try FileManager.default.copyItem(at: deliveries[0], to: duplicate)
    try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-86_400)], ofItemAtPath: duplicate.path)

    let all = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    #expect(try await pad.changedDeliveries(all, in: library).deliveries.isEmpty)
}

@Test func aDuplicateOfADeletedMaterialCannotResurrectIt() async throws {
    let (_, pad, deliveries, root) = try await twoDevices()
    let cloud = root.appending(path: "FNMN/deliveries")
    var library = try await pad.addCloudDelivery(deliveries[0], into: LibrarySnapshot())
    let duplicate = cloud.appending(path: "old-name.tar")
    try FileManager.default.copyItem(at: deliveries[0], to: duplicate)
    library = try library.applying(.delete(itemID: page.material.id), at: .now.addingTimeInterval(120))

    let all = try FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil)
    let found = try await pad.changedDeliveries(all, in: library)
    #expect(found.deliveries.isEmpty)
}

@Test func aCatalogFromBeforeDeletionsWereKeptLearnsThemFromTheJournals() async throws {
    let (phone, _, deliveries, root) = try await twoDevices()
    try await phone.appendJournal([JournalEvent(time: .now.addingTimeInterval(60), change: .library(.delete(itemID: page.material.id)))], device: "phone")
    let older = root.appending(path: "older")
    try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: older.appending(path: "state.json"))
    let device = LibraryFile(url: older, cache: root.appending(path: "older-cache"))
    await device.useCloudFolder(root.appending(path: "FNMN"))
    let (library, _) = try await device.load()

    let found = try await device.changedDeliveries(deliveries, in: library)
    #expect(found.deliveries.isEmpty)
    #expect(found.snapshot.deletedAt[page.material.id] != nil)
}

@Test func aJournalLineWithANoteThatHasNewlinesStaysOneLine() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
    let file = LibraryFile(url: root.appending(path: "app"))
    await file.useCloudFolder(cloud)
    let target = AnnotationTarget(materialID: "article:a", piece: 0, text: "text")
    let event = JournalEvent(time: Date(timeIntervalSince1970: 1_000), change: .library(.note("one\ntwo", target)))
    try await file.appendJournal([event], device: "phone")
    let journal = cloud.appending(path: "state/phone.jsonl")
    let lines = try String(contentsOf: journal, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: true)
    #expect(lines.count == 1)
    #expect(try JSONDecoder().decode(JournalEvent.self, from: Data(lines[0].utf8)) == event)
}

@Test func anArticleDeliveryRemovesTheArchiveOfTheLinkItReplaces() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud.appending(path: "deliveries"), withIntermediateDirectories: true)
    let pageURL = URL(string: "https://example.com/page")!
    let linkArchive = cloud.appending(path: "deliveries/link.tar")
    let articleArchive = cloud.appending(path: "deliveries/article.tar")
    try writeDelivery(ImportPackage.link(pageURL), to: linkArchive)
    try writeDelivery(ImportPackage(
        material: Material(id: "article:page", kind: .article, title: "Page", sourceURL: pageURL),
        sections: [], blocks: [], body: "A long enough body so the article has an excerpt."
    ), to: articleArchive)
    let file = LibraryFile(url: root.appending(path: "library"), cache: root.appending(path: "cache"))
    await file.useCloudFolder(cloud)

    var library = try await file.addCloudDelivery(linkArchive, into: LibrarySnapshot())
    #expect(library.articles.map(\.material.kind) == [.link])
    library = try await file.addCloudDelivery(articleArchive, into: library)

    #expect(library.articles.map(\.material.kind) == [.article])
    #expect(!FileManager.default.fileExists(atPath: linkArchive.path))
    #expect(FileManager.default.fileExists(atPath: articleArchive.path))
}

@Test func aLinkDeliveryShadowedByItsArticleIsNotReadAgain() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud.appending(path: "deliveries"), withIntermediateDirectories: true)
    let pageURL = URL(string: "https://example.com/page")!
    let linkArchive = cloud.appending(path: "deliveries/link.tar")
    try writeDelivery(ImportPackage.link(pageURL), to: linkArchive)
    let file = LibraryFile(url: root.appending(path: "library"), cache: root.appending(path: "cache"))
    await file.useCloudFolder(cloud)

    var library = LibrarySnapshot()
    try library.importPackage(ImportPackage(
        material: Material(id: "article:page", kind: .article, title: "Page", sourceURL: pageURL),
        sections: [], blocks: [], body: "A long enough body so the article has an excerpt."
    ), at: .now)

    let found = try await file.changedDeliveries([linkArchive], in: library)
    #expect(found.deliveries == [linkArchive])
    library = try await file.addCloudDelivery(linkArchive, into: found.snapshot)
    #expect(library.articles.map(\.material.id) == ["article:page"])
    #expect(try await file.changedDeliveries([linkArchive], in: library).deliveries.isEmpty)
}

@Test func aDeliveryForADeletedPagesTwinStaysOut() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud.appending(path: "deliveries"), withIntermediateDirectories: true)
    let pageURL = URL(string: "https://example.com/page")!
    let linkArchive = cloud.appending(path: "deliveries/link.tar")
    try writeDelivery(ImportPackage.link(pageURL), to: linkArchive)
    let file = LibraryFile(url: root.appending(path: "library"), cache: root.appending(path: "cache"))
    await file.useCloudFolder(cloud)

    var library = LibrarySnapshot()
    try library.importPackage(ImportPackage(
        material: Material(id: "article:page", kind: .article, title: "Page", sourceURL: pageURL),
        sections: [], blocks: [], body: "A long enough body so the article has an excerpt."
    ), at: .now)
    library = try library.applying(.delete(itemID: "article:page"))

    #expect(try await file.changedDeliveries([linkArchive], in: library).deliveries.isEmpty)
}

@Test func aDeletedMaterialTakesItsArchiveOutOfTheFolderSoNothingReadsItBackIn() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud.appending(path: "deliveries"), withIntermediateDirectories: true)
    let archive = cloud.appending(path: "deliveries/a.tar")
    try writeDelivery(illustrated, files: [("assets/cover.png", try png()), ("assets/diagram.png", try png())], to: archive)
    let file = LibraryFile(url: root.appending(path: "library"), cache: root.appending(path: "cache"))
    await file.useCloudFolder(cloud)
    let library = try await file.addCloudDelivery(archive, into: LibrarySnapshot())

    try await file.removeDelivery(of: try #require(library.articles.first))
    #expect(!FileManager.default.fileExists(atPath: archive.path))
    try await file.removeDelivery(of: try #require(library.articles.first))
}
