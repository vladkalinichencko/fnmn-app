import FNMNCore
import XCTest
@testable import FNMN

/// The digest store on the phone: what it takes from the FNMN folder, what it keeps on disk, and what it writes
/// back for the Mac's next training.
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
        DigestModel(device: "phone", file: DigestFile(url: root, cache: root))
    }

    private func package(id: String = "digest-2026-11-08T08-00-00Z") -> DigestPackage {
        let author = DigestPackage.Post.Author(handle: "karpathy", name: "Andrej Karpathy")
        let described = DigestPackage.Post(
            id: "x/1", network: "x", author: author,
            permalink: URL(string: "https://x.com/karpathy/status/1")!,
            postedAt: Date(timeIntervalSince1970: 1_760_000_000),
            text: "A small model that reads the whole catalog.",
            media: [.init(path: "assets/1.png", width: 640, height: 480)],
            folders: ["ml"]
        )
        let empty = DigestPackage.Post(
            id: "x/2", network: "x", author: author,
            permalink: URL(string: "https://x.com/karpathy/status/2")!,
            postedAt: Date(timeIntervalSince1970: 1_760_000_100),
            text: "A second post.", folders: ["ml"]
        )
        return DigestPackage(
            id: id,
            window: .init(from: Date(timeIntervalSince1970: 1_759_999_000), to: Date(timeIntervalSince1970: 1_760_001_000)),
            folders: ["ml"],
            sources: [.init(id: "x/karpathy", network: "x", name: "Andrej Karpathy", folders: ["ml"], status: "ok")],
            posts: [described, empty]
        )
    }

    private func writeDigest(_ package: DigestPackage, into folder: URL, name: String) throws -> URL {
        let url = folder.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeTar(package: package, to: url)
        return url
    }

    private func writeTar(package: DigestPackage, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var archive = Data()
        func add(_ name: String, _ data: Data) {
            var header = [UInt8](repeating: 0, count: 512)
            func put(_ text: String, at offset: Int) {
                for (index, byte) in text.utf8.enumerated() { header[offset + index] = byte }
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
        add("assets/1.png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        archive.append(Data(count: 1024))
        try archive.write(to: url)
    }

    func testSyncTakesANewDeliveryAndKeepsItInTheIndex() async throws {
        let folder = root.appending(path: "FNMN")
        _ = try writeDigest(package(), into: folder.appending(path: "digests"), name: "digest-1.tar")
        let digests = model()
        await digests.sync(folder: folder)
        XCTAssertEqual(digests.state, .ready)
        XCTAssertEqual(digests.digests.map(\.id), ["digest-2026-11-08T08-00-00Z"])
        let index = try await DigestFile(url: root, cache: root).loadIndex()
        XCTAssertEqual(index.imported.map(\.file), ["digest-1.tar"])
        await digests.sync(folder: folder)
        XCTAssertEqual(digests.digests.count, 1)
    }

    func testOpeningReadsWhatIsAlreadyUnpacked() async throws {
        let file = DigestFile(url: root, cache: root)
        let tar = try writeDigest(package(), into: root.appending(path: "incoming"), name: "digest-1.tar")
        _ = try await file.add(tar: tar)
        let digests = model()
        await digests.open()
        XCTAssertEqual(digests.state, .ready)
        XCTAssertEqual(digests.current?.package.posts.count, 2)
    }

    func testRecordingKeepsReadAndHiddenPostsAndWritesTheJournal() async throws {
        let folder = root.appending(path: "FNMN")
        let tar = try writeDigest(package(), into: folder.appending(path: "digests"), name: "digest-1.tar")
        let file = DigestFile(url: root, cache: root)
        _ = try await file.add(tar: tar)
        let digests = model()
        await digests.sync(folder: folder)
        let post = try XCTUnwrap(digests.post("x/1"))
        let digest = try XCTUnwrap(digests.digest(of: "x/1"))
        digests.record(.opened, post: post, digest: digest)
        digests.record(.hidden, post: post, digest: digest)
        await digests.settle()
        XCTAssertTrue(digests.seen.contains("x/1"))
        XCTAssertTrue(digests.hidden.contains("x/1"))
        let journal = folder.appending(path: "digest-state/phone.jsonl")
        let lines = try String(contentsOf: journal, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let last = try decoder.decode(DigestEngagement.self, from: Data(lines[1].utf8))
        XCTAssertEqual(last.kind, .hidden)
        XCTAssertEqual(last.postID, "x/1")
    }

    func testAHiddenPostLeavesItsSection() throws {
        let sections = package().sections(labels: [:], hidden: ["x/1"])
        XCTAssertEqual(sections.flatMap(\.posts).map(\.id), ["x/2"])
    }

    func testTheSearchFindsTextAndAuthor() {
        let package = package()
        XCTAssertEqual(package.posts(matching: "catalog").map(\.id), ["x/1"])
        XCTAssertEqual(package.posts(matching: "karpathy").count, 2)
    }
}
