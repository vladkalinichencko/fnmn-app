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
    context: DigestPackage.Post.Context? = nil
) -> DigestPackage.Post {
    DigestPackage.Post(
        id: id, network: .x, author: author, permalink: permalink, postedAt: date,
        text: text, media: media, context: context, folders: [folder]
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

/// The encoder `DigestFile` reads with: ISO 8601 dates in UTC.
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

/// Writes a digest delivery with its package and optional media files.
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
      "model": {"file": "classifier.mlmodel", "trainedAt": "2026-11-08T07:12:00Z", "examples": 231},
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
    #expect(decoded.model?.examples == 231)
    let post = try #require(decoded.posts.first)
    #expect(post.media.first?.width == 1280)
    #expect(post.video?.duration == 42)
    #expect(post.context?.kind == .quote)
    #expect(post.context?.post?.author.handle == "hardmaru")
    #expect(post.comments.first?.text == "This explains it.")
    #expect(post.stats?.likes == 100)
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
    let tar = try FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).tar")
    try writeTar(package: encoder().encode(package()), files: [("../evil.jpg", Data("x".utf8))], to: tar)
    await #expect(throws: DigestFileError.unsafePath("../evil.jpg")) {
        _ = try await file.add(tar: tar)
    }
}

@Test func theIndexSurvivesARoundtrip() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    let index = DigestIndex(
        imported: [.init(file: "digest-1.tar", id: "digest-1", at: postedAt)],
        seen: ["x/1"], hidden: ["x/2"]
    )
    try await file.saveIndex(index)
    let loaded = try await file.loadIndex()
    #expect(loaded == index)
}

@Test func engagementIsAppendedOneLineAtATime() async throws {
    let root = try temporaryFolder()
    let file = DigestFile(url: root, cache: root)
    let folder = try temporaryFolder()
    try await file.append(DigestEngagement(kind: .opened, postID: "x/1", digestID: "digest-1"), device: "phone", to: folder)
    try await file.append(DigestEngagement(kind: .saved, postID: "x/1", digestID: "digest-1"), device: "phone", to: folder)
    let journal = folder.appending(path: "digest-state/phone.jsonl")
    let lines = try String(contentsOf: journal, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 2)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let last = try decoder.decode(DigestEngagement.self, from: Data(lines[1].utf8))
    #expect(last.kind == .saved)
    #expect(last.postID == "x/1")
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

@Test func sectionsFollowTheFoldersAndTheClassifier() {
    let package = package(posts: [
        post("x/1", folder: "ml", date: postedAt),
        post("x/2", folder: "ml", date: postedAt.addingTimeInterval(-60)),
        post("x/3", folder: "design", date: postedAt),
        post("x/4", folder: "unknown", date: postedAt),
    ])
    let sections = package.sections(labels: ["x/2": "design"], hidden: [])
    #expect(sections.map(\.folder) == ["ml", "design", "unknown"])
    #expect(sections[0].posts.map(\.id) == ["x/1"])
    #expect(sections[1].posts.map(\.id) == ["x/3", "x/2"])
    #expect(sections[2].posts.map(\.id) == ["x/4"])
}

@Test func aHiddenPostLeavesItsSection() {
    let package = package(posts: [post("x/1"), post("x/2")])
    let sections = package.sections(labels: [:], hidden: ["x/2"])
    #expect(sections.flatMap(\.posts).map(\.id) == ["x/1"])
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

@Test func everyEngagementKindSurvivesTheJournal() throws {
    let encoder = encoder()
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    for kind in DigestEngagement.Kind.allCases {
        let event = DigestEngagement(kind: kind, postID: "x/1", digestID: "digest-1")
        let decoded = try decoder.decode(DigestEngagement.self, from: try encoder.encode(event))
        #expect(decoded.kind == kind)
        #expect(decoded.postID == "x/1")
    }
}
