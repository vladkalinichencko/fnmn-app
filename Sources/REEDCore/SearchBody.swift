import Foundation

public struct SearchParagraph: Codable, Equatable, Sendable {
    public let piece: Int
    public let markdown: String

    public init(piece: Int, markdown: String) {
        self.piece = piece
        self.markdown = markdown
    }
}

public struct SearchCue: Codable, Equatable, Sendable {
    public let seconds: Double
    public let text: String

    public init(seconds: Double, text: String) {
        self.seconds = seconds
        self.text = text
    }
}

public struct SearchBody: Codable, Equatable, Sendable {
    public let materialID: String
    public let paragraphs: [SearchParagraph]
    public let cues: [SearchCue]

    init(materialID: String, paragraphs: [SearchParagraph], cues: [SearchCue]) {
        self.materialID = materialID
        self.paragraphs = paragraphs
        self.cues = cues
    }

    public init(_ package: ImportPackage) {
        materialID = package.material.id
        let markdown = package.material.kind == .video ? "" : ArticleBody.readingMarkdown(body: package.body, blocks: package.blocks)
        paragraphs = ArticleBody.blocks(in: markdown).enumerated().compactMap { index, block in
            guard case let .text(text) = block else {
                return nil
            }
            return SearchParagraph(piece: index, markdown: text)
        }
        cues = package.blocks.compactMap { block in
            guard block.kind == .transcript, let seconds = block.startSeconds else {
                return nil
            }
            let text = block.html.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : SearchCue(seconds: seconds, text: text)
        }
    }
}

public enum SearchSource: String, CaseIterable, Codable, Sendable {
    case material, text, annotation, transcript

    public var title: String {
        switch self {
        case .material: "Titles"
        case .text: "In the Text"
        case .annotation: "Notes and Highlights"
        case .transcript: "Transcripts"
        }
    }
}

public struct SearchExcerpt: Equatable, Sendable {
    public let text: String
    public let span: TextSpan

    public init(text: String, span: TextSpan) {
        self.text = text
        self.span = span
    }
}

extension SearchExcerpt {
    public static func around(_ text: String, span: TextSpan, limit: Int = 180) -> SearchExcerpt {
        let paragraph = text.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        let found = NSIntersectionRange(NSRange(location: span.start, length: span.length), NSRange(location: 0, length: paragraph.length))
        guard paragraph.length > limit else {
            return SearchExcerpt(text: paragraph as String, span: TextSpan(start: found.location, length: found.length))
        }
        var start = max(found.location - 50, 0)
        if start > 0 {
            let space = paragraph.range(of: " ", options: .backwards, range: NSRange(location: 0, length: start))
            start = space.location == NSNotFound ? 0 : space.location + 1
        }
        var end = min(start + limit, paragraph.length)
        if end < paragraph.length {
            let space = paragraph.range(of: " ", options: .backwards, range: NSRange(location: start, length: end - start))
            end = space.location == NSNotFound ? paragraph.rangeOfComposedCharacterSequence(at: end).location : space.location
        }
        let lead = start > 0 ? "…" : ""
        let tail = end < paragraph.length ? "…" : ""
        let window = NSRange(location: start, length: end - start)
        let inside = NSIntersectionRange(found, window)
        let shifted = TextSpan(start: inside.location - start + lead.utf16.count, length: inside.length)
        return SearchExcerpt(text: lead + paragraph.substring(with: window) + tail, span: shifted)
    }
}

public struct SearchHit: Equatable, Sendable {
    public let itemID: String
    public let source: SearchSource
    public let piece: Int?
    public let seconds: Double?
    public let text: String
    public let span: TextSpan?

    public init(itemID: String, source: SearchSource, piece: Int? = nil, seconds: Double? = nil, text: String, span: TextSpan? = nil) {
        self.itemID = itemID
        self.source = source
        self.piece = piece
        self.seconds = seconds
        self.text = text
        self.span = span
    }
}

extension SearchHit: Identifiable {
    public var id: String {
        let piece = piece.map(String.init) ?? "-"
        let time = seconds.map { String(format: "%.2f", $0) } ?? "-"
        return "\(source.rawValue)#\(itemID)#\(piece)#\(time)#\(span?.start ?? -1)#\(span?.length ?? 0)"
    }
}
