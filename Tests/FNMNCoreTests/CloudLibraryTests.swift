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

/// Two devices on one FNMN folder: the phone stores a delivery, and the pad finds it by looking at the folder.
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
    // A second delete, or a file already gone, is not an error.
    try await file.removeDelivery(of: try #require(library.articles.first))
}
