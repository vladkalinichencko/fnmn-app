import Foundation
import XCTest

final class ArchitectureGuardTests: XCTestCase {
    private func contents(of file: String) throws -> String {
        try String(contentsOf: try AppSources.file(named: file), encoding: .utf8)
    }

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

    func testPostCardsShareTheirParts() throws {
        for file in ["PostCard.swift", "ThreadScreen.swift"] {
            let source = try contents(of: file)
            XCTAssertTrue(source.contains("PostText("), "\(file) builds its own post text")
            XCTAssertTrue(source.contains("PostOpenButton("), "\(file) builds its own open button")
        }
        for file in try AppSources.files() {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("PostAuthorLine"), "\(file.lastPathComponent) still draws its own author line")
        }
    }

    func testMediaCoverIsOfferedTheZoomNamespace() throws {
        for file in try AppSources.files() {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains(".presentsMedia(") else {
                continue
            }
            guard let cover = source.range(of: ".presentsMedia("),
                  let zoom = source.range(of: ".environment(\\.mediaZoom") else {
                continue
            }
            XCTAssertLessThan(
                cover.lowerBound,
                zoom.lowerBound,
                "\(file.lastPathComponent) presents media above the mediaZoom injection, so the cover never sees the namespace and zoom falls back to a slide"
            )
        }
    }

    func testTabSearchSharesOneOverlay() throws {
        for file in ["LibraryScreen.swift", "DigestScreen.swift", "ShelfScreen.swift"] {
            XCTAssertTrue(try contents(of: file).contains(".searchResults(query:"), "\(file) builds its own search overlay")
        }
        for file in ["SearchResults.swift", "DigestSearchResults.swift"] {
            XCTAssertTrue(try contents(of: file).contains("SearchResultsList("), "\(file) draws its own results chrome")
        }
        for file in try AppSources.files() where file.lastPathComponent != "ScreenSearch.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("ContentUnavailableView.search"), "\(file.lastPathComponent) draws its own empty-search view")
            XCTAssertFalse(source.contains("scrollContentBackground(.hidden)"), "\(file.lastPathComponent) hides a list background outside the shared results chrome")
        }
    }

    func testWebViewsAppearOnlyInTheLiveCropAndThePlayer() throws {
        let allowed: Set<String> = ["LiveCropView.swift", "VideoReaderView.swift"]
        for file in try AppSources.files() {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains("import WebKit") || source.contains("WKWebView") else {
                continue
            }
            XCTAssertTrue(
                allowed.contains(file.lastPathComponent),
                "\(file.lastPathComponent) opens a web view; only the live crop and the embedded player may, and a third place is a decision to write down here"
            )
        }
    }
}
