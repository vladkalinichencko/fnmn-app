@testable import FNMNCore
import Foundation
import Testing

@Suite struct DigestChaosTests {
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func digest() -> DigestPackage {
        DigestPackage(
            id: "digest-chaos",
            window: .init(from: Date(timeIntervalSince1970: 1_760_000_000), to: Date(timeIntervalSince1970: 1_760_003_600)),
            folders: ["ml"],
            posts: []
        )
    }

    @Test func everyEntryNameStaysInsideTheDigest() async throws {
        let names = [
            "../evil.jpg", "/etc/passwd", "", "a/../../b.jpg", "assets/../../x.jpg",
            "good.jpg", "assets/ok.jpg", "ファイル.jpg", "a b.jpg", ".hidden", "a//b.jpg", "a/./b.jpg",
        ]
        for name in names {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = DigestFile(url: root, cache: root)
            let tar = root.appending(path: "incoming.tar")
            try writeTar(package: try encoder().encode(digest()), files: [(name, Data("x".utf8))], to: tar)
            do {
                let added = try await file.add(tar: tar)
                let inside = try FileManager.default.subpathsOfDirectory(atPath: added.folder.path)
                #expect(inside.allSatisfy { !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") })
                #expect(!FileManager.default.fileExists(atPath: root.appending(path: "evil.jpg").path))
            } catch {
                #expect(!FileManager.default.fileExists(atPath: root.appending(path: "evil.jpg").path))
            }
        }
    }

    @Test func randomBytesNeverBecomeADigest() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = DigestFile(url: root, cache: root)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func nextByte() -> UInt8 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8((seed >> 33) & 0xFF)
        }
        for attempt in 0 ..< 40 {
            let tar = root.appending(path: "random-\(attempt).tar")
            let count = Int(nextByte()) + 1
            try Data((0 ..< count).map { _ in nextByte() }).write(to: tar)
            do {
                _ = try await file.add(tar: tar)
                Issue.record("random bytes became a digest")
            } catch {
            }
        }
        #expect((try? await file.packages())?.isEmpty ?? false)
    }

    @Test func aLargeFileArrivesByteForByte() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = DigestFile(url: root, cache: root)
        let payload = Data((0 ..< 200_000).map { UInt8($0 % 251) })
        let tar = root.appending(path: "large.tar")
        try writeTar(package: try encoder().encode(digest()), files: [("assets/large.bin", payload)], to: tar)
        let added = try await file.add(tar: tar)
        #expect(try Data(contentsOf: added.url(of: "assets/large.bin")) == payload)
    }

    @Test func aDigestWithAUnicodeIDLandsInItsOwnFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = DigestFile(url: root, cache: root)
        let package = DigestPackage(
            id: "digest-文件-2026-11-08",
            window: .init(from: Date(timeIntervalSince1970: 1_760_000_000), to: Date(timeIntervalSince1970: 1_760_003_600))
        )
        let tar = root.appending(path: "unicode.tar")
        try writeTar(package: try encoder().encode(package), files: [], to: tar)
        let added = try await file.add(tar: tar)
        #expect(added.folder.lastPathComponent == "digest-文件-2026-11-08")
        #expect(try await file.packages().count == 1)
    }

    @Test func aRealDeliveryFromTheMacDecodes() throws {
        let url = try #require(
            Bundle.module.url(forResource: "digest-package", withExtension: "json", subdirectory: "Fixtures")
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(DigestPackage.self, from: Data(contentsOf: url))
        #expect(package.schema == DigestPackage.supportedSchema)
        #expect(package.posts.count == 3)
        #expect(package.sources.first?.network == .telegram)
        #expect(package.sources.first?.status == .ok)
        #expect(package.posts.allSatisfy { $0.text?.isEmpty == false })
        #expect(package.sections(labels: [:], hidden: []).count == 1)
    }
}
