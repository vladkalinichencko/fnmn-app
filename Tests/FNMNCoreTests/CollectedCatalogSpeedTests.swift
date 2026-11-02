@testable import FNMNCore
import Foundation
import Testing

/// Screens draw from the catalog the model collected once; these selectors over collected materials
/// must not quietly become a new rebuild of the whole catalog, or the sheet and the search go back
/// to collecting in a view body.
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

    @Test func selectorsOverCollectedMaterialsDoFarLessThanCollecting() {
        let library = Self.library
        let catalog = library.items

        func lowestOverRuns(_ runs: Int, _ body: () -> Void) -> Double {
            _ = body() // warm up
            let clock = ContinuousClock()
            var times: [Double] = []
            for _ in 0 ..< runs {
                let start = clock.now
                body()
                let end = clock.now
                times.append(Double((end - start) / .milliseconds(1)))
            }
            return times.min()!
        }

        // The rebuild the screens must never do while a sheet or a keystroke waits.
        let collect = lowestOverRuns(3) { _ = library.albumSummaries }
        // What they actually run, over the collected list.
        let along = lowestOverRuns(10) { _ = library.albumSummaries(among: catalog) }

        #expect(along < collect / 5, "alongside took \(along) ms, collecting took \(collect) ms")
    }
}
