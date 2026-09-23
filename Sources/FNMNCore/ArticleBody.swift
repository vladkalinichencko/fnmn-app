import Foundation

public enum ArticleRun: Equatable, Sendable {
    case text(String)
    case math(String)
}

public enum ArticlePiece: Equatable, Sendable {
    case paragraph([ArticleRun])
    case displayMath(String)
    case image(alt: String, path: String)
    case video(path: String)
    case interactive(url: URL, selector: String?)
}

public struct ArticleHeading: Equatable, Identifiable, Sendable {
    public let level: Int
    public let title: String
    public let piece: Int
    public var id: Int { piece }
}

public enum ArticleBody {
    public static func headings(in markdown: String) -> [ArticleHeading] {
        pieces(in: markdown).enumerated().compactMap { index, piece in
            guard case let .paragraph(runs) = piece, let heading = heading(runs) else { return nil }
            return ArticleHeading(level: heading.level, title: heading.title, piece: index)
        }
    }

    public static func legacyPiece(for position: ReadingPosition, in package: ImportPackage) -> Int? {
        guard position.pieceIndex == nil, package.material.kind == .article else { return nil }
        guard let block = package.blocks.first(where: { $0.id == position.blockID }),
              let index = package.sections.firstIndex(where: { $0.id == block.sectionID }) else { return nil }
        let headings = headings(in: readingMarkdown(body: package.body, blocks: package.blocks))
        guard headings.indices.contains(index) else { return nil }
        return headings[index].piece
    }

    public static func readingMarkdown(body: String?, blocks: [Block]) -> String {
        if let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }
        return blocks.compactMap { block in
            let text = plain(block.html)
            switch block.kind {
            case .heading:
                return text.isEmpty ? nil : "## \(text)"
            case .image:
                guard let url = block.mediaURL else { return text.isEmpty ? nil : text }
                return "![\(text)](\(url.absoluteString))"
            default:
                return text.isEmpty ? nil : text
            }
        }.joined(separator: "\n\n")
    }

    public static func pieces(in markdown: String) -> [ArticlePiece] {
        var pieces: [ArticlePiece] = []
        var rest = markdown[...]
        while let open = rest.range(of: "```") {
            appendProse(String(rest[..<open.lowerBound]), to: &pieces)
            rest = rest[open.upperBound...]
            guard let close = rest.range(of: "```") else {
                appendProse("```" + rest, to: &pieces)
                return pieces
            }
            appendFence(String(rest[..<close.lowerBound]), to: &pieces)
            rest = rest[close.upperBound...]
        }
        appendProse(String(rest), to: &pieces)
        return pieces
    }

    public static func headingOrdinals(in pieces: [ArticlePiece]) -> [Int?] {
        var count = 0
        return pieces.map { piece in
            guard case let .paragraph(runs) = piece, heading(runs) != nil else { return nil }
            count += 1
            return count
        }
    }

    public static func heading(_ runs: [ArticleRun]) -> (level: Int, title: String)? {
        guard case let .text(source) = runs.first else { return nil }
        let start = source.drop(while: { $0 == " " || $0 == "\t" })
        guard let match = start.prefixMatch(of: /(#{1,6})[ \t]+/) else { return nil }
        let remainder = start[match.range.upperBound...]
        guard !remainder.contains("\n"), !runs.dropFirst().contains(where: containsBreak) else { return nil }
        let title = ([String(remainder)] + runs.dropFirst().map(plainRun)).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return (match.1.count, title)
    }

    public static func headingBody(_ runs: [ArticleRun]) -> [ArticleRun]? {
        guard heading(runs) != nil, case let .text(source) = runs.first else { return nil }
        let start = source.drop(while: { $0 == " " || $0 == "\t" })
        guard let match = start.prefixMatch(of: /(#{1,6})[ \t]+/) else { return nil }
        return [.text(String(start[match.range.upperBound...]))] + runs.dropFirst()
    }

    private static func containsBreak(_ run: ArticleRun) -> Bool {
        guard case let .text(text) = run else { return false }
        return text.contains("\n")
    }

    private static func plainRun(_ run: ArticleRun) -> String {
        switch run {
        case let .text(text): text
        case let .math(latex): "$\(latex)$"
        }
    }

    private static func appendFence(_ raw: String, to pieces: inout [ArticlePiece]) {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let kind = lines.first ?? ""
        let body = lines.dropFirst().filter { !$0.isEmpty }
        if kind == "fnmn-interactive", let address = body.first, let url = URL(string: address), url.scheme == "http" || url.scheme == "https" {
            pieces.append(.interactive(url: url, selector: body.dropFirst().first))
            return
        }
        if kind == "fnmn-video", let path = body.first {
            pieces.append(.video(path: path))
            return
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            pieces.append(.paragraph([.text("```\n\(text)\n```")]))
        }
    }

    private static func appendProse(_ raw: String, to pieces: inout [ArticlePiece]) {
        var rest = raw[...]
        while let open = rest.range(of: "$$") {
            appendPlain(String(rest[..<open.lowerBound]), to: &pieces)
            rest = rest[open.upperBound...]
            guard let close = rest.range(of: "$$") else {
                appendPlain("$$" + rest, to: &pieces)
                return
            }
            let latex = rest[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !latex.isEmpty {
                pieces.append(.displayMath(latex))
            }
            rest = rest[close.upperBound...]
        }
        appendPlain(String(rest), to: &pieces)
    }

    private static func appendPlain(_ raw: String, to pieces: inout [ArticlePiece]) {
        for paragraph in raw.components(separatedBy: "\n\n") {
            appendParagraph(paragraph[...], to: &pieces)
        }
    }

    private static func appendParagraph(_ raw: Substring, to pieces: inout [ArticlePiece]) {
        var runs: [ArticleRun] = []
        var cursor = raw[...]
        func flush() {
            let kept = runs.filter { run in
                guard case let .text(text) = run else { return true }
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !kept.isEmpty {
                pieces.append(.paragraph(kept))
            }
            runs = []
        }
        while !cursor.isEmpty {
            if cursor.hasPrefix("![") {
                flush()
                cursor = cursor.dropFirst(2)
                guard let altEnd = cursor.firstIndex(of: "]") else {
                    pieces.append(.paragraph([.text("![" + cursor)]))
                    return
                }
                let paren = cursor.index(after: altEnd)
                guard paren < cursor.endIndex, cursor[paren] == "(", let pathEnd = cursor[cursor.index(after: paren)...].firstIndex(of: ")") else {
                    pieces.append(.paragraph([.text("![" + cursor)]))
                    return
                }
                let alt = String(cursor[..<altEnd])
                let path = String(cursor[cursor.index(after: paren)..<pathEnd])
                pieces.append(.image(alt: alt, path: path))
                cursor = cursor[cursor.index(after: pathEnd)...]
                continue
            }
            if cursor.first == "`" {
                let after = cursor.index(after: cursor.startIndex)
                if let end = cursor[after...].firstIndex(of: "`") {
                    appendText(String(cursor[...end]), to: &runs)
                    cursor = cursor[cursor.index(after: end)...]
                    continue
                }
            }
            if let latex = inlineMath(at: &cursor) {
                runs.append(.math(latex))
                continue
            }
            let next = cursor.firstIndex { $0 == "$" || $0 == "`" } ?? cursor.endIndex
            let image = cursor.range(of: "![")?.lowerBound ?? cursor.endIndex
            let stop = min(next, image)
            if stop == cursor.startIndex {
                appendText(String(cursor.prefix(1)), to: &runs)
                cursor = cursor.dropFirst()
            } else {
                appendText(String(cursor[..<stop]), to: &runs)
                cursor = cursor[stop...]
            }
        }
        flush()
    }

    private static func appendText(_ text: String, to runs: inout [ArticleRun]) {
        if case let .text(existing) = runs.last {
            runs[runs.count - 1] = .text(existing + text)
        } else {
            runs.append(.text(text))
        }
    }

    private static func inlineMath(at cursor: inout Substring) -> String? {
        guard cursor.first == "$" else { return nil }
        let after = cursor.index(after: cursor.startIndex)
        guard after < cursor.endIndex, cursor[after] != "$", cursor[after] != " ", cursor[after] != "\n" else { return nil }
        var index = after
        while index < cursor.endIndex, cursor[index] != "\n" {
            if cursor[index] == "$" {
                let previous = cursor.index(before: index)
                guard cursor[previous] != " ", cursor[previous] != "\n" else { return nil }
                let latex = String(cursor[after..<index])
                cursor = cursor[cursor.index(after: index)...]
                return latex
            }
            index = cursor.index(after: index)
        }
        return nil
    }

    private static func plain(_ html: String) -> String {
        html.replacing(/<[^>]+>/, with: " ")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
