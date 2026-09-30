// Parses every `$…$` and `$$…$$` of a Markdown file with the app's SwiftUIMath and counts the formulas it
// cannot read, by error, with one example each. The app shows those as their LaTeX source.
//   swift run MathProbe <content.md>
import Foundation
@testable import SwiftUIMath

let path = CommandLine.arguments.dropFirst().first ?? "content.md"
let markdown = try String(contentsOfFile: path, encoding: .utf8)
let formulas = markdown.matches(of: /(?s)\$\$(.+?)\$\$|\$(?!\$)([^$\n]+?)\$/).map { match in
    String(match.output.1 ?? match.output.2 ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
}

var failures: [String: (count: Int, example: String)] = [:]
for latex in formulas {
    var error: Math.ParserError?
    guard Math.Parser.build(fromString: latex, error: &error) == nil else { continue }
    let message = error?.message ?? "no atoms"
    failures[message, default: (0, latex)].count += 1
}

print("\(failures.values.map(\.count).reduce(0, +)) of \(formulas.count) formulas do not parse")
for (message, failure) in failures.sorted(by: { $0.value.count > $1.value.count }) {
    print(failure.count, message, "  e.g.", failure.example.prefix(120))
}
