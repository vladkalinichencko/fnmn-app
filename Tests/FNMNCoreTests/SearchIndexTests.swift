import Foundation
import Testing
@testable import FNMNCore

private func delivery(_ body: String, id: String) -> ImportPackage {
    ImportPackage(
        material: Material(id: id, kind: .article, title: "Searchable", sourceURL: URL(string: "https://example.com/s")),
        sections: [],
        blocks: [],
        body: body
    )
}

@Test func aDeliveryLaysItsTextOutForTheSearchWhenItArrives() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud.appending(path: "deliveries"), withIntermediateDirectories: true)
    let package = delivery("Opening words.\n\nA paragraph with a needle in it.\n\nClosing words.", id: "article:search")
    let archive = cloud.appending(path: "deliveries/a.tar")
    try DeliveryArchive.write(package, files: [], to: archive)

    let file = LibraryFile(url: root.appending(path: "library"), cache: root.appending(path: "cache"))
    await file.useCloudFolder(cloud)
    _ = try await file.addCloudDelivery(archive, into: LibrarySnapshot())

    let bodies = try await file.searchBodies()
    let body = try #require(bodies["article:search"])
    #expect(body.paragraphs.count == 3)
    #expect(body.paragraphs.map(\.piece) == [0, 1, 2])
    #expect(body.paragraphs[1].markdown.contains("needle"))
    #expect(body.cues.isEmpty)
}

@Test func theIndexGoesWhenTheMaterialDoes() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cloud = root.appending(path: "FNMN")
    try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
    let archive = root.appending(path: "a.tar")
    try DeliveryArchive.write(delivery("Only words.", id: "article:gone"), files: [], to: archive)
    let file = LibraryFile(url: root.appending(path: "library"), cache: root.appending(path: "cache"))
    await file.useCloudFolder(cloud)
    _ = try await file.storeArticle(archive: archive, into: LibrarySnapshot())
    #expect(try await file.searchBodies().keys.contains("article:gone"))

    await file.removeSearchBody("article:gone")
    #expect(try await file.searchBodies().isEmpty)
}
