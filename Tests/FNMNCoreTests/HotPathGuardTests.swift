@testable import FNMNCore
import Foundation
import XCTest

/// A guard test standing for the lint rule this repo wrote after the 2026-11-01 jank: a view body
/// collects the catalog again and again — on every reshuffle of the screen, each keystroke of the
/// search and each wake of `LibraryModel`, where the sheet and a scroll share the frame. The pass is
/// expensive (~10 ms per 1500 materials on a Mac, more on a phone), so screens read the lists
/// `LibraryModel` collects once per catalog change, and only the model calls these selectors.
final class HotPathGuardTests: XCTestCase {
    private static let forbiddenSelectors: [(selector: String, why: String)] = [
        ("snapshot.items(", "collects the catalog; read the model's list"),
        ("snapshot.albumSummaries", "collects the catalog; read the model's list"),
        ("snapshot.unsortedItems", "collects the catalog; read the model's list"),
        ("snapshot.continueItems", "collects the catalog; read the model's list"),
        ("snapshot.groups(", "collects the catalog; read the model's list"),
        ("snapshot.archivedItems", "collects the catalog; read the model's list"),
        ("snapshot.annotationGroups", "collects the catalog; read the model's list"),
    ]

    /// The one file allowed to collect: the model's wrappers and the catalog refresh live there.
    private static let allowed = "LibraryModel.swift"

    func testViewBodiesDoNotCollectTheCatalog() throws {
        let url = URL(fileURLWithPath: #filePath)
        let root = sequence(first: url.deletingLastPathComponent(), next: { $0.deletingLastPathComponent() })
            .first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("App").path) })
        guard let root else { return XCTFail("The test needs the repository root: App/ beside Package.swift.") }
        let files = try XCTUnwrap(try FileManager.default
            .enumerator(at: root.appending(path: "App/FNMN"), includingPropertiesForKeys: nil)?
            .allObjects
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" })

        var hits: [String] = []
        for file in files {
            let lines = try (String(contentsOf: file, encoding: .utf8)).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains("snapshot.") && file.lastPathComponent != Self.allowed {
                for (selector, why) in Self.forbiddenSelectors where line.contains(selector) {
                    hits.append("\(file.lastPathComponent):\(index + 1) — \(selector) \(why) (\(line.trimmed))")
                }
            }
        }
        XCTAssertTrue(hits.isEmpty, "The catalog is collected in view code again:\n\(hits.joined(separator: "\n"))")
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespaces)
    }
}
