import Foundation
import XCTest

final class ServerLinkGuardTests: XCTestCase {
    private static let owner = "ServerLink.swift"

    func testReadersOfTheSavedConnectionAskForIt() throws {
        var hits: [String] = []
        for file in try AppSources.files() where file.lastPathComponent != Self.owner {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            let reads = lines.enumerated().filter { $0.element.contains("server.connection") }
            guard !reads.isEmpty else {
                continue
            }
            guard !lines.contains(where: { $0.contains("savedConnection()") }) else {
                continue
            }
            for (index, line) in reads {
                hits.append("\(file.lastPathComponent):\(index + 1) — \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertTrue(
            hits.isEmpty,
            "A reader of server.connection never calls server.savedConnection(), so the lazy read has not run:\n\(hits.joined(separator: "\n"))"
        )
    }
}
