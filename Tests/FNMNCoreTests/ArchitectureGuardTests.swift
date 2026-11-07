import Foundation
import XCTest

/// Source guards for boundaries the compiler cannot see: which file owns disk work, and when a lazy read runs.
/// They read the whole app, not the lines one change adds.
final class ArchitectureGuardTests: XCTestCase {
    private func contents(of file: String) throws -> String {
        try String(contentsOf: try AppSources.file(named: file), encoding: .utf8)
    }

    /// The body between the first `{` after `declaration` and its matching `}`.
    private func body(of declaration: String, in source: String) -> String? {
        guard let start = source.range(of: declaration),
              let open = source[start.upperBound...].firstIndex(of: "{") else {
            return nil
        }
        var depth = 0
        var index = open
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[open...index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    func testLibraryModelDoesNotOwnTheJournalOrTheImportDiskWork() throws {
        let source = try contents(of: "LibraryModel.swift")
        let banned = [
            "appendJournal(", "loadSync(", "saveSync(", "unreadJournalEvents(", "changedDeliveries(",
            "addCloudDelivery(", "applyBrowserCatalog(", "storeArticle(", "storeMade(", "moveIntoCloud(",
            "holdsMaterialsInApp(", "package(ofFile",
        ]
        let lines = source.components(separatedBy: "\n")
        let hits = lines.enumerated().flatMap { index, line in
            banned.filter { line.contains($0) }.map { "LibraryModel.swift:\(index + 1) — \($0)" }
        }
        XCTAssertTrue(hits.isEmpty, "LibraryModel took back journal or import disk work:\n\(hits.joined(separator: "\n"))")
    }

    func testServerLinkReadsTheKeychainOnlyWhenAsked() throws {
        let source = try contents(of: "ServerLink.swift")
        let initBody = try XCTUnwrap(body(of: "init(port:", in: source))
        XCTAssertFalse(initBody.contains("storage.load()"), "ServerLink.init reads the Keychain while the app starts")
        let saved = try XCTUnwrap(body(of: "func savedConnection(", in: source))
        XCTAssertTrue(saved.contains("storage.load()"), "savedConnection() no longer reads the saved connection")
    }

    /// The magazine draws its posts with SwiftUI, never with a browser: a web view would bring the network's
    /// own page, its scripts and its layout into a tab that must look like the rest of the app.
    func testTheDigestTabDrawsWithSwiftUINotWebViews() throws {
        let digest = try AppSources.files().filter { $0.path.contains("/Digest/") }
        XCTAssertFalse(digest.isEmpty, "App/FNMN/Digest holds no sources; the guard would pass on nothing")
        for file in digest {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("import WebKit"), "\(file.lastPathComponent) imports WebKit; the digest draws natively")
            XCTAssertFalse(source.contains("WKWebView"), "\(file.lastPathComponent) opens a web view; the digest draws natively")
        }
    }
}
