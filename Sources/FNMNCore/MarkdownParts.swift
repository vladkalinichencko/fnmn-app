import Foundation

/// Where one part of Markdown ends and the next begins: a blank line, except inside a code fence or a `$$`
/// formula; a heading is a part of its own. The column and the speed reader split the same way.
enum MarkdownParts {
    /// A heading line, as its level and the title after it.
    static func heading(_ line: String) -> (level: Int, title: String)? {
        guard let match = line.prefixMatch(of: /(#{1,6})[ \t]+(.+)/) else {
            return nil
        }
        let title = String(match.2).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : (match.1.count, title)
    }

    /// A line of three or more dashes, stars or underscores, with nothing else on it.
    static func isThematicBreak(_ line: String) -> Bool {
        let marks = line.filter { !$0.isWhitespace }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else {
            return false
        }
        return marks.allSatisfy { $0 == first }
    }

    /// The parts of a document, in order. A rule between parts goes; one under a line of text stays that line's.
    static func split(_ markdown: String) -> [String] {
        var parts: [String] = []
        var lines: [Substring] = []
        var fenced = false
        var inMath = false

        func flush() {
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            lines = []
            guard !text.isEmpty else {
                return
            }
            parts.append(text)
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fenced {
                lines.append(line)
                if trimmed.hasPrefix("```"), lines.count > 1 {
                    flush()
                    fenced = false
                }
                continue
            }
            if inMath {
                lines.append(line)
                if trimmed.components(separatedBy: "$$").count.isMultiple(of: 2) {
                    inMath = false
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                flush()
                fenced = true
                lines = [line]
                continue
            }
            if trimmed.isEmpty {
                flush()
                continue
            }
            if heading(trimmed) != nil {
                flush()
                parts.append(trimmed)
                continue
            }
            if lines.isEmpty, isThematicBreak(trimmed) {
                continue
            }
            lines.append(line)
            if trimmed.components(separatedBy: "$$").count.isMultiple(of: 2) {
                inMath = true
            }
        }
        flush()
        return parts
    }
}
