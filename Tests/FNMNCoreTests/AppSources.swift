import Foundation
import XCTest

enum AppSources {
    static func files() throws -> [URL] {
        let url = URL(fileURLWithPath: #filePath)
        let root = sequence(first: url.deletingLastPathComponent(), next: { $0.deletingLastPathComponent() })
            .first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("App").path) })
        let app = try XCTUnwrap(root?.appending(path: "App/FNMN"), "The test needs the repository root: App/ beside Package.swift.")
        let files = FileManager.default
            .enumerator(at: app, includingPropertiesForKeys: nil)?
            .allObjects
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        return try XCTUnwrap(files, "The test needs the app's sources under App/FNMN.")
    }

    static func file(named name: String) throws -> URL {
        let match = try files().first { $0.lastPathComponent == name }
        return try XCTUnwrap(match, "App/FNMN has no \(name).")
    }
}
