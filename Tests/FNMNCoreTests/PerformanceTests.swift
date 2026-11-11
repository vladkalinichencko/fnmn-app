@testable import FNMNCore
import Foundation
import XCTest

final class PerformanceTests: XCTestCase {
    private static let body = (1...40).map { index in
        index % 8 == 1 ? "## Section \(index)" : "Paragraph \(index) explains the idea with a formula $x^\(index)$ and a [link](https://example.com/\(index))."
    }.joined(separator: "\n\n")

    private static let library: LibrarySnapshot = {
        var library = LibrarySnapshot()
        for index in 0..<1500 {
            let url = URL(string: "https://site\(index % 90).example.com/post/\(index)")!
            let package = ImportPackage(
                material: Material(id: "article:\(url)", kind: .article, title: "Article \(index) on kernels", sourceURL: url),
                sections: [],
                blocks: [],
                folders: ["Album \(index % 12)"],
                body: body
            )
            try! library.importPackage(package, at: Date(timeIntervalSinceReferenceDate: Double(index)))
        }
        return library
    }()

    func testSearchKeystroke() {
        let queries = LibraryQueries(Self.library)
        measure { _ = queries.items(matching: "Section 17") }
    }

    func testBuildingEveryTile() {
        let library = Self.library
        measure { _ = LibraryQueries(library) }
    }

    func testLibraryScreenSelectors() {
        let queries = LibraryQueries(Self.library)
        measure {
            _ = queries.unsortedItems
            _ = queries.albumSummaries
        }
    }

    func testOpeningADocument() {
        let markdown = Array(repeating: Self.body, count: 10).joined(separator: "\n\n")
        measure { _ = ReaderDocument(markdown: markdown, title: "Article") }
    }
}
