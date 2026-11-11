@testable import FNMNCore
import Foundation
import XCTest

final class HotPathGuardTests: XCTestCase {
    private static let allowed = "LibraryModel.swift"

    func testViewBodiesDoNotBuildTheCatalog() throws {
        let files = try AppSources.files()
            .filter { $0.lastPathComponent != Self.allowed }

        var hits: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains("LibraryQueries(") {
                hits.append("\(file.lastPathComponent):\(index + 1) — \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertTrue(hits.isEmpty, "The catalog is built in view code:\n\(hits.joined(separator: "\n"))")
    }
}
