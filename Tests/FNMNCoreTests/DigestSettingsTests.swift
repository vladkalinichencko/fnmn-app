import Foundation
import Testing
@testable import FNMNCore

struct DigestSettingsTests {
    @Test func aMissingFileReadsAsTheDefaults() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = DigestSettings.load(from: folder)
        #expect(settings.enabled)
        #expect(settings.hours == [8, 20])
        #expect(settings.threshold == 0.5)
        #expect(settings.limit == 40)
        #expect(settings.networks.isEmpty)
        #expect(settings.sources.isEmpty)
    }

    @Test func aSavedFileReadsBack() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = DigestSettings()
        settings.enabled = false
        settings.hours = [7, 19]
        settings.threshold = 0.35
        settings.limit = 60
        settings.networks["x"] = .init(recommendations: true, topics: ["llms"])
        settings.sources["x/karpathy"] = .init(topics: ["neural nets"])
        try settings.save(to: folder)
        #expect(DigestSettings.load(from: folder) == settings)
    }

    @Test func theWireKeysAreTheOnesTheServerReads() throws {
        var settings = DigestSettings()
        settings.networks["telegram"] = .init(topics: ["crypto"])
        let data = try JSONEncoder().encode(settings)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["enabled"] as? Bool == true)
        #expect(json["hours"] as? [Int] == [8, 20])
        #expect(json["threshold"] as? Double == 0.5)
        #expect(json["limit"] as? Int == 40)
        let networks = try #require(json["networks"] as? [String: Any])
        let telegram = try #require(networks["telegram"] as? [String: Any])
        #expect(telegram["topics"] as? [String] == ["crypto"])
        #expect(telegram["recommendations"] as? Bool == false)
        #expect((json["sources"] as? [String: Any])?.isEmpty == true)
    }

    @Test func aPartialFileReadsWithDefaults() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"enabled": false, "networks": {"x": {"topics": ["rust"]}}}"#.utf8)
            .write(to: folder.appending(path: DigestSettings.fileName))
        let settings = DigestSettings.load(from: folder)
        #expect(!settings.enabled)
        #expect(settings.hours == [8, 20])
        #expect(settings.networks["x"]?.topics == ["rust"])
        #expect(settings.networks["x"]?.recommendations == false)
    }
}
