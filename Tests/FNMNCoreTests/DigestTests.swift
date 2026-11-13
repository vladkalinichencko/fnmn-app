@testable import FNMNCore
import Foundation
import Testing

private let author = DigestPackage.Post.Author(handle: "karpathy", name: "Andrej Karpathy")
private let permalink = URL(string: "https://x.com/karpathy/status/1587")!
private let postedAt = Date(timeIntervalSince1970: 1_760_000_000)

private func post(
    _ id: String,
    folder: String = "ml",
    date: Date = postedAt,
    text: String = "A small model that reads the whole catalog.",
    media: [DigestPackage.Post.Media] = [],
    context: DigestPackage.Post.Context? = nil,
    comments: [DigestPackage.Post.Comment] = []
) -> DigestPackage.Post {
    DigestPackage.Post(
        id: id, network: .x, author: author, permalink: permalink, postedAt: date,
        text: text, media: media, context: context, comments: comments, folders: [folder]
    )
}

private func package(
    id: String = "digest-2026-11-08T08:00:00Z",
    window: DigestPackage.Window = .init(from: postedAt.addingTimeInterval(-3600), to: postedAt),
    folders: [String] = ["ml", "design"],
    posts: [DigestPackage.Post] = [post("x/1")]
) -> DigestPackage {
    DigestPackage(id: id, window: window, folders: folders, posts: posts)
}

private func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func writeDigest(_ package: DigestPackage, files: [(String, Data)] = [("assets/1.jpg", Data("jpg".utf8))]) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).tar")
    try writeTar(package: try encoder().encode(package), files: files, to: url)
    return url
}

@Test func aDigestPackageDecodesTheServersJSON() throws {
    let json = """
    {
      "schema": 1,
      "id": "digest-2026-11-08T08:00:00Z",
      "window": {"from": "2026-11-07T20:00:00Z", "to": "2026-11-08T08:00:00Z"},
      "folders": ["ml", "design"],
      "sources": [
        {"id": "x/karpathy", "network": "x", "name": "Andrej Karpathy", "folders": ["ml"], "status": "ok"},
        {"id": "tg/durov", "network": "telegram", "name": "Pavel Durov", "folders": ["design"], "status": "stale", "detail": "the login expired"}
      ],
      "posts": [{
        "id": "x/1587", "network": "x",
        "author": {"handle": "karpathy", "name": "Andrej Karpathy"},
        "permalink": "https://x.com/karpathy/status/1587",
        "postedAt": "2026-11-08T07:00:00Z",
        "text": "A small model that reads the whole catalog.",
        "media": [{"path": "assets/1587-0.jpg", "width": 1280, "height": 720}],
        "video": {"poster": {"path": "assets/1587-poster.jpg", "width": 640, "height": 360}, "duration": 42.0},
        "context": {"kind": "quote", "post": {
          "id": "x/1000", "network": "x",
          "author": {"handle": "hardmaru", "name": "hardmaru"},
          "permalink": "https://x.com/hardmaru/status/1000",
          "postedAt": "2026-11-07T21:00:00Z",
          "text": "The post being quoted.",
          "media": []
        }},
        "comments": [{"author": "someone", "text": "This explains it.", "permalink": "https://x.com/someone/status/1"}],
        "stats": {"likes": 100, "reposts": 5, "replies": 2},
        "folders": ["ml"]
      }]
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(DigestPackage.self, from: Data(json.utf8))
    #expect(decoded.id == "digest-2026-11-08T08:00:00Z")
    #expect(decoded.folders == ["ml", "design"])
    #expect(decoded.sources[1].status == .stale)
    let post = try #require(decoded.posts.first)
    #expect(post.media.first?.width == 1280)
    #expect(post.video?.duration == 42)
    #expect(post.context?.kind == .quote)
    #expect(post.context?.post?.author.handle == "hardmaru")
    #expect(post.comments.first?.text == "This explains it.")
    #expect(post.stats?.likes == 100)
}

@Test func aSourceWithANullNameFallsBackToItsID() throws {
    let json = """
    {
      "schema": 1,
      "id": "digest-2026-11-13T07:00:04Z",
      "window": {"from": "2026-11-12T20:00:00Z", "to": "2026-11-13T07:00:00Z"},
      "folders": [],
      "sources": [
        {"id": "instagram/makkkkkksimka", "network": "instagram", "name": null, "folders": [], "status": "ok"}
      ],
      "posts": []
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(DigestPackage.self, from: Data(json.utf8))
    #expect(decoded.sources.first?.name == "instagram/makkkkkksimka")
}

@Test func aDigestTarUnpacksItsFilesIntoTheCache() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    let tar = try writeDigest(package())
    let digest = try await file.add(tar: tar)
    #expect(FileManager.default.fileExists(atPath: digest.url(of: "assets/1.jpg").path))
    #expect(FileManager.default.fileExists(atPath: digest.folder.appending(path: "package.json").path))
    let listed = try await file.packages()
    #expect(listed.map(\.id) == ["digest-2026-11-08T08:00:00Z"])
    #expect(listed.first?.package.posts.count == 1)
}

@Test func addingTheSameDigestAgainReplacesIt() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    _ = try await file.add(tar: try writeDigest(package()))
    let replaced = try await file.add(tar: try writeDigest(package(), files: [("assets/1.jpg", Data("new".utf8))]))
    let data = try Data(contentsOf: replaced.url(of: "assets/1.jpg"))
    #expect(data == Data("new".utf8))
    #expect(try await file.packages().count == 1)
}

@Test func anUnsafePathIsRefused() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    let tar = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).tar")
    try writeTar(package: encoder().encode(package()), files: [("../evil.jpg", Data("x".utf8))], to: tar)
    await #expect(throws: DigestFileError.unsafePath("../evil.jpg")) {
        _ = try await file.add(tar: tar)
    }
}

@Test func aFileNamedDotIsRefused() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    let tar = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).tar")
    try writeTar(package: encoder().encode(package()), files: [(".", Data("x".utf8))], to: tar)
    await #expect(throws: DigestFileError.unsafePath(".")) {
        _ = try await file.add(tar: tar)
    }
}

@Test func theIndexSurvivesARoundtrip() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    let index = DigestIndex(
        imported: [.init(file: "digest-1.tar", id: "digest-1", at: postedAt)],
        hidden: ["x/2"]
    )
    try await file.saveIndex(index)
    let loaded = try await file.loadIndex()
    #expect(loaded == index)
}

@Test func aRefreshedPictureLandsInTheDigestAndAHostileNameIsRefused() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    let digest = try await file.add(tar: try writeDigest(package()))
    let path = try await file.saveMedia(Data("picture".utf8), as: "refresh-1.jpg", of: digest)
    #expect(path == "media/refresh-1.jpg")
    #expect(try Data(contentsOf: digest.url(of: path)) == Data("picture".utf8))
    await #expect(throws: DigestFileError.unsafePath("media/../x.jpg")) {
        _ = try await file.saveMedia(Data("x".utf8), as: "../x.jpg", of: digest)
    }
}

@Test func evictionKeepsTheNewestDigests() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    for hour in 0 ..< 3 {
        let end = postedAt.addingTimeInterval(Double(hour) * 3600)
        let window = DigestPackage.Window(from: end.addingTimeInterval(-3600), to: end)
        _ = try await file.add(tar: try writeDigest(package(id: "digest-\(hour)", window: window)))
    }
    try await file.evict(keeping: 2)
    let left = try await file.packages()
    #expect(left.map(\.id) == ["digest-2", "digest-1"])
}

@Test func sectionsFollowTheNetworksThenTheFolders() {
    let package = package(posts: [
        post("x/1", folder: "ml", date: postedAt),
        post("x/2", folder: "ml", date: postedAt.addingTimeInterval(-60)),
        post("x/3", folder: "design", date: postedAt),
        post("x/4", folder: "unknown", date: postedAt),
    ])
    let sections = package.sections(hidden: [])
    #expect(sections.map(\.network) == [.x])
    let topics = sections[0].topics
    #expect(topics.map(\.folder) == ["ml", "design", "unknown"])
    #expect(topics[0].posts.map(\.id) == ["x/1", "x/2"])
    #expect(topics[1].posts.map(\.id) == ["x/3"])
    #expect(topics[2].posts.map(\.id) == ["x/4"])
}

@Test func networksComeInTheirOrder() {
    let package = package(posts: [
        post("x/1"),
        DigestPackage.Post(id: "tg/1", network: .telegram, author: author, permalink: permalink, postedAt: postedAt, text: "tg", folders: ["ml"]),
    ])
    #expect(package.sections(hidden: []).map(\.network) == [.telegram, .x])
}

@Test func aHiddenPostLeavesItsSection() {
    let package = package(posts: [post("x/1"), post("x/2")])
    let sections = package.sections(hidden: ["x/2"])
    #expect(sections.flatMap { $0.topics.flatMap(\.posts) }.map(\.id) == ["x/1"])
}

@Test func searchReadsTextAndAuthor() {
    let package = package(posts: [
        post("x/1", text: "A small model that reads the whole catalog."),
        post("x/2", text: "Nothing about that here."),
    ])
    #expect(package.posts(matching: "catalog").map(\.id) == ["x/1"])
    #expect(package.posts(matching: "karpathy").count == 2)
    #expect(package.posts(matching: "  ").count == 2)
}

@Test func aTextOnlyDigestUnpacks() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    let digest = try await file.add(tar: try writeDigest(package(), files: []))
    #expect(digest.package.posts.count == 1)
    #expect(try await file.packages().count == 1)
}

@Test func aDigestIDThatCannotBeAFolderIsRefused() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    for id in ["", ".", "..", "/tmp/x", "a\\b"] {
        let tar = try writeDigest(package(id: id), files: [])
        await #expect(throws: DigestFileError.unsafeID(id)) {
            _ = try await file.add(tar: tar)
        }
    }
}

@Test func aDigestIDWithASlashLandsInOneFolder() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    let added = try await file.add(tar: try writeDigest(package(id: "digest/one"), files: []))
    #expect(added.folder.lastPathComponent == "digest-one")
}

@Test func aDigestFromANewerSchemaIsRefused() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    let newer = DigestPackage(
        schema: DigestPackage.supportedSchema + 1,
        id: "digest-newer",
        window: .init(from: postedAt, to: postedAt)
    )
    await #expect(throws: DigestFileError.unsupportedSchema(DigestPackage.supportedSchema + 1)) {
        _ = try await file.add(tar: try writeDigest(newer, files: []))
    }
}

@Test func searchSkipsHiddenPosts() {
    let package = package(posts: [
        post("x/1", text: "A catalog post."),
        post("x/2", text: "Another catalog post."),
    ])
    #expect(package.posts(matching: "catalog", hidden: ["x/2"]).map(\.id) == ["x/1"])
    #expect(package.posts(matching: "", hidden: ["x/1"]).map(\.id) == ["x/2"])
}

@Test func searchFoldsCaseAndDiacritics() {
    let post = DigestPackage.Post(
        id: "x/1",
        network: .x,
        author: .init(handle: "ada", name: "Ada Lovelace"),
        permalink: URL(string: "https://x.com/ada/status/1")!,
        postedAt: Date(timeIntervalSince1970: 1_000),
        text: "A café in Zürich",
        folders: ["ml"]
    )
    let package = DigestPackage(
        id: "digest-1",
        window: .init(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 2_000)),
        posts: [post]
    )
    #expect(package.posts(matching: "cafe").map(\.id) == ["x/1"])
    #expect(package.posts(matching: "ZURICH").map(\.id) == ["x/1"])
}

@Test func searchReachesQuotedPostsAndComments() {
    let quoted = DigestPackage.Post.ContextPost(
        id: "x/9", network: .x,
        author: .init(handle: "hardmaru", name: "hardmaru"),
        permalink: URL(string: "https://x.com/hardmaru/status/9")!,
        postedAt: postedAt,
        text: "A benchmark nobody talks about."
    )
    let found = post(
        "x/1",
        text: "My own words.",
        context: .init(kind: .quote, post: quoted),
        comments: [.init(author: "reader", handle: "reader", text: "this benchmark convinced me")]
    )
    let package = package(posts: [post("x/2", text: "Unrelated."), found])
    #expect(package.posts(matching: "benchmark").map(\.id) == ["x/1"])
    #expect(package.posts(matching: "hardmaru").map(\.id) == ["x/1"])
    #expect(package.posts(matching: "convinced").map(\.id) == ["x/1"])
}

@Test func anExcerptMarksTheMatch() {
    let found = post("x/1", text: "The quick brown fox jumps over the lazy dog.")
    let excerpt = found.excerpt(matching: "brown fox")
    #expect(excerpt?.text == "The quick brown fox jumps over the lazy dog.")
    #expect(excerpt.map { String(excerpt!.text.dropFirst($0.span.start).prefix($0.span.length)) } == "brown fox")
    #expect(found.excerpt(matching: "nothing") == nil)
}


