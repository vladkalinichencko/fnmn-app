@testable import FNMNCore
import Foundation
import Testing

/// Screens draw from the collected catalog, so a selector over it must fit the frame budget (5 ms).
struct CollectedCatalogSpeedTests {
    private static let library: LibrarySnapshot = {
        var library = LibrarySnapshot()
        let body = (1 ... 40).map { index in
            index % 8 == 1 ? "## Section \(index)" : "Paragraph \(index) explains the idea with a [link](https://example.com/\(index))."
        }.joined(separator: "\n\n")
        for index in 0 ..< 1500 {
            let package = ImportPackage(
                material: Material(id: "article:\(index)", kind: .article, title: "Article \(index) on kernels", sourceURL: URL(string: "https://site\(index % 90).example.com/post/\(index)")),
                sections: [], blocks: [], folders: ["Album \(index % 12)"], body: body
            )
            try! library.importPackage(package, at: Date(timeIntervalSinceReferenceDate: Double(index)))
        }
        return library
    }()

    @Test func albumSummariesOverCollectedMaterialsFitTheFrameBudget() {
        let library = Self.library
        let catalog = library.items
        var best = Double.infinity
        for _ in 0 ..< 10 {
            let start = ContinuousClock.now
            _ = library.albumSummaries(among: catalog)
            best = min(best, Double((ContinuousClock.now - start) / .milliseconds(1)))
        }
        #expect(best < 5, "albumSummaries over the collected catalog took \(best) ms at best")
    }
}
