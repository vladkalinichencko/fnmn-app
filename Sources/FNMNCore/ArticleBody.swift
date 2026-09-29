import Foundation

/// One unit of the reading column. A text block is drawn on its own plate; headings sit on the background.
public enum DocumentBlock: Equatable, Sendable {
    case heading(level: Int, title: String)
    /// A paragraph, list, quote, table or code block, with any formula or picture that stands inside it.
    case text(String)
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
    /// Splits Markdown into reading blocks. A blank line ends a block, except inside a code fence or a `$$` formula;
    /// a heading line is always its own block. Pictures and code belong to the prose around them, never stand alone.
    public static func blocks(in markdown: String) -> [DocumentBlock] {
        attachingFigures(rawBlocks(in: markdown))
    }

    private static func rawBlocks(in markdown: String) -> [DocumentBlock] {
        var blocks: [DocumentBlock] = []
        var lines: [Substring] = []
        var fence: Substring?
        var inMath = false

        func flush() {
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            lines = []
            guard !text.isEmpty else { return }
            blocks.append(block(text, fence: fence))
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fence != nil {
                lines.append(line)
                if trimmed.hasPrefix("```"), lines.count > 1 {
                    flush()
                    fence = nil
                }
                continue
            }
            if inMath {
                lines.append(line)
                if trimmed.components(separatedBy: "$$").count.isMultiple(of: 2) { inMath = false }
                continue
            }
            if trimmed.hasPrefix("```") {
                flush()
                fence = line
                lines = [line]
                continue
            }
            if trimmed.isEmpty {
                flush()
                continue
            }
            if let heading = heading(trimmed) {
                flush()
                blocks.append(heading)
                continue
            }
            lines.append(line)
            if trimmed.components(separatedBy: "$$").count.isMultiple(of: 2) { inMath = true }
        }
        flush()
        return blocks
    }

    /// A picture or code block joins the paragraph before it; after a heading it joins the paragraph that follows.
    /// Only a picture that opens the document, before any prose, stays on its own: it is the article's cover.
    private static func attachingFigures(_ blocks: [DocumentBlock]) -> [DocumentBlock] {
        var result: [DocumentBlock] = []
        var waiting: [String] = []
        var seenProse = false

        func flushWaiting() {
            guard !waiting.isEmpty else { return }
            result.append(.text(waiting.joined(separator: "\n\n")))
            waiting = []
        }

        for block in blocks {
            if let figure = figureMarkdown(block) {
                if !seenProse, case .image = block {
                    result.append(block)
                } else if case let .text(previous)? = result.last, waiting.isEmpty {
                    result[result.count - 1] = .text(previous + "\n\n" + figure)
                } else {
                    waiting.append(figure)
                }
            } else if case let .text(prose) = block {
                result.append(.text((waiting + [prose]).joined(separator: "\n\n")))
                waiting = []
                seenProse = true
            } else {
                flushWaiting()
                result.append(block)
            }
        }
        flushWaiting()
        return result
    }

    /// The Markdown of a block that belongs inside a paragraph's plate: a picture or a code fence.
    private static func figureMarkdown(_ block: DocumentBlock) -> String? {
        switch block {
        case let .image(alt, path): "![\(alt)](\(path))"
        case let .text(text) where text.hasPrefix("```"): text
        default: nil
        }
    }

    /// Every local picture a block of Markdown shows, in order.
    public static func imagePaths(in markdown: String) -> [String] {
        markdown.matches(of: /!\[[^\]]*\]\(([^)\s]+)\)/).map { String($0.1) }
    }

    public static func headings(in markdown: String) -> [ArticleHeading] {
        blocks(in: markdown).enumerated().compactMap { index, block in
            guard case let .heading(level, title) = block else { return nil }
            return ArticleHeading(level: level, title: title, piece: index)
        }
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

    public static func legacyPiece(for position: ReadingPosition, in package: ImportPackage) -> Int? {
        guard position.pieceIndex == nil, package.material.kind == .article else { return nil }
        guard let block = package.blocks.first(where: { $0.id == position.blockID }),
              let index = package.sections.firstIndex(where: { $0.id == block.sectionID }) else { return nil }
        let headings = headings(in: readingMarkdown(body: package.body, blocks: package.blocks))
        guard headings.indices.contains(index) else { return nil }
        return headings[index].piece
    }

    /// The opening prose of an article for its tile: the first paragraph that is not a heading, picture, formula, code or table.
    public static func excerpt(_ body: String?, limit: Int = 220) -> String? {
        guard let body else { return nil }
        for block in body.prefix(20_000).components(separatedBy: "\n\n") {
            let text = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = text.first, !"#!`$|<>".contains(first) else { continue }
            let prose = text.components(separatedBy: "$").first ?? text
            let plain = prose
                .replacing(/!?\[([^\]]*)\]\([^)]*\)/) { $0.1 }
                .replacing(/[*_`$]/, with: "")
                .replacing(/\s+/, with: " ")
            guard plain.count > 40 else { continue }
            return String(plain.prefix(limit))
        }
        return nil
    }

    /// The first local raster picture of an article, the one its tile shows; tiles cannot draw SVG.
    public static func firstImagePath(_ body: String) -> String? {
        for match in body.prefix(40_000).matches(of: /!\[[^\]]*\]\(([^)\s]+)\)/) {
            let path = String(match.1)
            let kind = (path as NSString).pathExtension.lowercased()
            if !path.hasPrefix("http"), ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(kind) { return path }
        }
        return nil
    }

    private static func heading(_ line: String) -> DocumentBlock? {
        guard let match = line.prefixMatch(of: /(#{1,6})[ \t]+(.+)/) else { return nil }
        let title = String(match.2).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : .heading(level: match.1.count, title: title)
    }

    private static func block(_ text: String, fence: Substring?) -> DocumentBlock {
        if let fence {
            let kind = fence.trimmingCharacters(in: .whitespaces).dropFirst(3)
            let body = text.split(separator: "\n").dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if kind == "fnmn-interactive", let address = body.first, let url = URL(string: address), url.scheme == "http" || url.scheme == "https" {
                return .interactive(url: url, selector: body.dropFirst().first)
            }
            if kind == "fnmn-video", let path = body.first {
                return .video(path: path)
            }
            return .text(text)
        }
        if let match = text.wholeMatch(of: /!\[([^\]]*)\]\(([^)\s]+)\)/) {
            return .image(alt: String(match.1), path: String(match.2))
        }
        return .text(text)
    }

    private static func plain(_ html: String) -> String {
        html.replacing(/<[^>]+>/, with: " ")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
