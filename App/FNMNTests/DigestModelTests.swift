import FNMNCore
import Observation
import XCTest
@testable import FNMN

@MainActor
final class DigestModelTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "digest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func model() -> DigestModel {
        DigestModel(file: DigestFile(url: root, cache: root))
    }

    private func package(id: String = "digest-2026-11-08T08-00-00Z") -> DigestPackage {
        let author = DigestPackage.Post.Author(handle: "karpathy", name: "Andrej Karpathy")
        let described = DigestPackage.Post(
            id: "x/1", network: .x, author: author,
            permalink: URL(string: "https://x.com/karpathy/status/1")!,
            postedAt: Date(timeIntervalSince1970: 1_760_000_000),
            text: "A small model that reads the whole catalog.",
            media: [.init(path: "assets/1.png", width: 640, height: 480)],
            folders: ["ml"]
        )
        let empty = DigestPackage.Post(
            id: "x/2", network: .x, author: author,
            permalink: URL(string: "https://x.com/karpathy/status/2")!,
            postedAt: Date(timeIntervalSince1970: 1_760_000_100),
            text: "A second post.", folders: ["ml"]
        )
        return DigestPackage(
            id: id,
            window: .init(from: Date(timeIntervalSince1970: 1_759_999_000), to: Date(timeIntervalSince1970: 1_760_001_000)),
            folders: ["ml"],
            sources: [.init(id: "x/karpathy", network: .x, name: "Andrej Karpathy", folders: ["ml"], status: .ok)],
            posts: [described, empty]
        )
    }

    private func writeDigest(
        _ package: DigestPackage,
        into folder: URL,
        name: String,
        files: [(String, Data)] = [("assets/1.png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))]
    ) throws -> URL {
        let url = folder.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeTar(package: package, to: url, files: files)
        return url
    }

    private func writeTar(
        package: DigestPackage,
        to url: URL,
        files: [(String, Data)] = [("assets/1.png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))]
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var archive = Data()
        func add(_ name: String, _ data: Data) {
            var header = [UInt8](repeating: 0, count: 512)
            func put(_ text: String, at offset: Int) {
                for (index, byte) in text.utf8.enumerated() {
                    header[offset + index] = byte
                }
            }
            put(name, at: 0)
            put("0000644", at: 100)
            put("0000000", at: 108)
            put("0000000", at: 116)
            put(String(format: "%011o", data.count), at: 124)
            put("00000000000", at: 136)
            put("        ", at: 148)
            put("0", at: 156)
            put("ustar", at: 257)
            put("00", at: 263)
            put(String(format: "%06o", header.reduce(0) { $0 + Int($1) }), at: 148)
            archive.append(contentsOf: header)
            archive.append(data)
            archive.append(Data(count: (512 - data.count % 512) % 512))
        }
        add("package.json", try encoder.encode(package))
        for (name, data) in files {
            add(name, data)
        }
        archive.append(Data(count: 1024))
        try archive.write(to: url)
    }

    func testSyncTakesANewDeliveryAndKeepsItInTheIndex() async throws {
        let folder = root.appending(path: "FNMN")
        _ = try writeDigest(package(), into: folder.appending(path: "digests"), name: "digest-1.tar")
        let digests = model()
        await digests.sync(folder: folder)
        XCTAssertEqual(digests.state, .ready)
        XCTAssertEqual(digests.syncState, .idle)
        XCTAssertEqual(digests.digests.map(\.id), ["digest-2026-11-08T08-00-00Z"])
        let index = try await DigestFile(url: root, cache: root).loadIndex()
        XCTAssertEqual(index.imported.map(\.file), ["digest-1.tar"])
        await digests.sync(folder: folder)
        XCTAssertEqual(digests.digests.count, 1)
    }

    func testSyncWithNoFolderReadsTheCache() async throws {
        let file = DigestFile(url: root, cache: root)
        let tar = try writeDigest(package(), into: root.appending(path: "incoming"), name: "digest-1.tar")
        _ = try await file.add(tar: tar)
        let digests = model()
        await digests.sync(folder: nil)
        XCTAssertEqual(digests.state, .ready)
        XCTAssertEqual(digests.current?.package.posts.count, 2)
    }

    func testHidingAPostKeepsItOutOfTheSections() async throws {
        let folder = root.appending(path: "FNMN")
        let tar = try writeDigest(package(), into: folder.appending(path: "digests"), name: "digest-1.tar")
        let file = DigestFile(url: root, cache: root)
        _ = try await file.add(tar: tar)
        let digests = model()
        await digests.sync(folder: folder)
        let post = try XCTUnwrap(digests.post("x/1"))
        digests.hide(post)
        await digests.settle()
        XCTAssertTrue(digests.hidden.contains("x/1"))
        let saved = try await DigestFile(url: root, cache: root).loadIndex()
        XCTAssertTrue(saved.hidden.contains("x/1"))
    }

    func testFoldingASectionKeepsItOutOfTheIndex() async throws {
        let folder = root.appending(path: "FNMN")
        _ = try writeDigest(package(), into: folder.appending(path: "digests"), name: "digest-1.tar")
        let digests = model()
        await digests.sync(folder: folder)
        let fold: DigestFold = .network(digest: "digest-2026-11-08T08-00-00Z", network: .x)
        digests.toggleFold(fold)
        XCTAssertTrue(digests.folded.contains(fold))
        await digests.settle()
        let saved = try await DigestFile(url: root, cache: root).loadIndex()
        XCTAssertTrue(saved.folded.contains(fold))
        digests.toggleFold(fold)
        XCTAssertFalse(digests.folded.contains(fold))
    }

    func testAHiddenPostLeavesItsSection() throws {
        let sections = package().sections(hidden: ["x/1"])
        XCTAssertEqual(sections.flatMap { $0.topics.flatMap(\.posts) }.map(\.id), ["x/2"])
    }

    func testTheSearchFindsTextAndAuthor() {
        let package = package()
        XCTAssertEqual(package.posts(matching: "catalog").map(\.id), ["x/1"])
        XCTAssertEqual(package.posts(matching: "karpathy").count, 2)
    }

    func testASyncBeforeOpenKeepsTheHiddenPosts() async throws {
        let folder = root.appending(path: "FNMN")
        _ = try writeDigest(package(), into: folder.appending(path: "digests"), name: "digest-1.tar")
        let file = DigestFile(url: root, cache: root)
        try await file.saveIndex(DigestIndex(hidden: ["x/2"]))
        let digests = model()
        await digests.sync(folder: folder)
        XCTAssertEqual(digests.hidden, ["x/2"])
        let saved = try await DigestFile(url: root, cache: root).loadIndex()
        XCTAssertEqual(saved.hidden, ["x/2"])
    }

    func testABadDeliveryKeepsTheGoodOneAndTheMagazine() async throws {
        let folder = root.appending(path: "FNMN")
        let newer = DigestPackage(
            schema: DigestPackage.supportedSchema + 1,
            id: "digest-bad",
            window: .init(from: Date(timeIntervalSince1970: 1_759_999_000), to: Date(timeIntervalSince1970: 1_760_001_000))
        )
        _ = try writeDigest(newer, into: folder.appending(path: "digests"), name: "a-bad.tar", files: [])
        _ = try writeDigest(package(id: "digest-good"), into: folder.appending(path: "digests"), name: "b-good.tar")
        let digests = model()
        await digests.sync(folder: folder)
        XCTAssertEqual(digests.state, .ready)
        XCTAssertEqual(digests.digests.map(\.id), ["digest-good"])
        XCTAssertNotNil(digests.lastError)
    }

    func testACachePurgeRestoresTheDigest() async throws {
        let folder = root.appending(path: "FNMN")
        _ = try writeDigest(package(id: "digest-good"), into: folder.appending(path: "digests"), name: "digest-1.tar")
        let digests = model()
        await digests.sync(folder: folder)
        XCTAssertEqual(digests.digests.count, 1)
        try FileManager.default.removeItem(at: root.appending(path: "digests/digest-good"))
        await digests.sync(folder: folder)
        XCTAssertEqual(digests.digests.map(\.id), ["digest-good"])
        XCTAssertNil(digests.lastError)
    }

    func testATextOnlyDeliveryIsTaken() async throws {
        let folder = root.appending(path: "FNMN")
        _ = try writeDigest(package(id: "digest-text"), into: folder.appending(path: "digests"), name: "digest-1.tar", files: [])
        let digests = model()
        await digests.sync(folder: folder)
        XCTAssertEqual(digests.current?.package.posts.count, 2)
        XCTAssertNil(digests.lastError)
    }

    func testSearchUsesTheHiddenSet() async throws {
        let folder = root.appending(path: "FNMN")
        _ = try writeDigest(package(), into: folder.appending(path: "digests"), name: "digest-1.tar")
        let digests = model()
        await digests.sync(folder: folder)
        let post = try XCTUnwrap(digests.post("x/1"))
        digests.hide(post)
        let package = try XCTUnwrap(digests.current?.package)
        let found = package.posts(matching: "karpathy", hidden: digests.hidden)
        XCTAssertEqual(found.map(\.id), ["x/2"])
    }

    func testEveryNetworkAndContextKindHasADisplay() {
        for network in DigestPackage.Network.allCases {
            XCTAssertFalse(network.name.isEmpty)
        }
        for kind in DigestPackage.Post.Context.Kind.allCases {
            XCTAssertFalse(PostCard.icon(kind).isEmpty)
            let context = DigestPackage.Post.Context(kind: kind)
            XCTAssertEqual(PostCard.contextLabel(context), "\(kind.action) a post that is gone")
        }
    }

    func testAContextKindNamesThePostItShows() {
        let parent = DigestPackage.Post.ContextPost(
            id: "x/0",
            network: .x,
            author: .init(handle: "ada", name: "Ada"),
            permalink: URL(string: "https://x.com/ada/status/0")!,
            postedAt: Date(timeIntervalSince1970: 1_759_999_000)
        )
        for kind in DigestPackage.Post.Context.Kind.allCases {
            let label = PostCard.contextLabel(DigestPackage.Post.Context(kind: kind, post: parent))
            XCTAssertEqual(label, "\(kind.action) Ada")
        }
    }

    func testAContextOnlyPostIsFoundForItsThread() async throws {
        let folder = root.appending(path: "FNMN")
        let parent = DigestPackage.Post.ContextPost(
            id: "x/0",
            network: .x,
            author: .init(handle: "ada", name: "Ada"),
            permalink: URL(string: "https://x.com/ada/status/0")!,
            postedAt: Date(timeIntervalSince1970: 1_759_999_000),
            text: "the whole parent text"
        )
        let reply = DigestPackage.Post(
            id: "x/1",
            network: .x,
            author: .init(handle: "bob", name: "Bob"),
            permalink: URL(string: "https://x.com/bob/status/1")!,
            postedAt: Date(timeIntervalSince1970: 1_760_000_000),
            context: .init(kind: .reply, post: parent)
        )
        let package = DigestPackage(
            id: "digest-context",
            window: .init(from: Date(timeIntervalSince1970: 1_759_999_000), to: Date(timeIntervalSince1970: 1_760_001_000)),
            posts: [reply]
        )
        _ = try writeDigest(package, into: folder.appending(path: "digests"), name: "digest-context.tar", files: [])
        let digests = model()
        await digests.sync(folder: folder)
        XCTAssertNil(digests.post("x/0"))
        XCTAssertEqual(digests.contextPost("x/0")?.text, "the whole parent text")
        XCTAssertNil(digests.contextPost("x/9"))
    }

    func testHidingAMarkNotifiesTheReader() async throws {
        let folder = root.appending(path: "FNMN")
        _ = try writeDigest(package(), into: folder.appending(path: "digests"), name: "digest-1.tar")
        let digests = model()
        await digests.sync(folder: folder)
        let post = try XCTUnwrap(digests.post("x/1"))
        let seen = expectation(description: "the reader sees the mark")
        withObservationTracking {
            _ = digests.hidden
        } onChange: {
            seen.fulfill()
        }
        digests.hide(post)
        await fulfillment(of: [seen], timeout: 1)
    }

    func testARefreshBringsOnePicture() async throws {
        let folder = root.appending(path: "FNMN")
        _ = try writeDigest(package(), into: folder.appending(path: "digests"), name: "digest-1.tar")
        let port = FakeServerPort()
        port.media = [.init(path: "media/p.jpg", width: 2, height: 2)]
        let connection = try ServerConnection(address: "https://example.com", token: "token")
        let server = ServerLink(port: port, storage: FakeStorage(connection: connection))
        let digests = DigestModel(file: DigestFile(url: root, cache: root), server: server)
        await digests.sync(folder: folder)
        let post = try XCTUnwrap(digests.post("x/1"))
        let digest = try XCTUnwrap(digests.digest(of: "x/1"))
        await digests.refresh(post, digest: digest)
        XCTAssertEqual(digests.media(for: post).map(\.path), ["media/refresh-p.jpg"])
        XCTAssertEqual(try Data(contentsOf: digest.url(of: "media/refresh-p.jpg")), Data("picture".utf8))
        XCTAssertTrue(digests.refreshing.isEmpty)
    }
}

@MainActor
private final class FakeServerPort: ServerPort {
    var media: [DigestPackage.Post.Media] = []
    var data = Data("picture".utf8)

    func check(connection: ServerConnection) async throws {
    }

    func startJob(url: URL, connection: ServerConnection) async throws -> ServerJob {
        throw URLError(.unsupportedURL)
    }

    func startFileJob(file: URL, connection: ServerConnection, onStep: @escaping @MainActor (ImportStep) -> Void) async throws -> ServerJob {
        throw URLError(.unsupportedURL)
    }

    func job(_ id: String, connection: ServerConnection) async throws -> ServerJob {
        throw URLError(.unsupportedURL)
    }

    func delivery(of id: String, connection: ServerConnection, onStep: @escaping @MainActor (ImportStep) -> Void) async throws -> URL {
        throw URLError(.unsupportedURL)
    }

    func startVideoDownload(url: URL, connection: ServerConnection) async throws -> ServerJob {
        throw URLError(.unsupportedURL)
    }

    func videoFile(of id: String, connection: ServerConnection, onStep: @escaping @MainActor (ImportStep) -> Void) async throws -> URL {
        throw URLError(.unsupportedURL)
    }

    func forget(_ id: String, connection: ServerConnection) async throws {
    }

    func refreshDigestPost(_ postID: String, connection: ServerConnection) async throws -> [DigestPackage.Post.Media] {
        media
    }

    func digestMedia(_ name: String, connection: ServerConnection) async throws -> Data {
        data
    }
}

private struct FakeStorage: ServerConnectionStorage {
    let connection: ServerConnection

    func load() -> ServerConnection? {
        connection
    }

    func save(_ connection: ServerConnection) throws {
    }
}
