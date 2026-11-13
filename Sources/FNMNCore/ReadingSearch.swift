import Foundation

public struct TextMatch: Equatable, Sendable {
    public let piece: Int
    public let span: TextSpan

    public init(piece: Int, span: TextSpan) {
        self.piece = piece
        self.span = span
    }
}

public enum ReadingSearch {
    private static let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    public static func matches(of query: String, in texts: [Int: String]) -> [TextMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return []
        }
        return texts.keys.sorted().flatMap { piece in
            spans(of: needle, in: texts[piece] ?? "").map { TextMatch(piece: piece, span: $0) }
        }
    }

    public static func spans(of needle: String, in text: String) -> [TextSpan] {
        let text = text as NSString
        var spans = literalSpans(of: needle, in: text)
        if spans.isEmpty, needle.contains(where: \.isWhitespace) {
            spans = whitespaceSpans(of: needle, in: text)
        }
        return spans
    }

    private static func literalSpans(of needle: String, in text: NSString) -> [TextSpan] {
        var spans: [TextSpan] = []
        var start = 0
        while start < text.length {
            let found = text.range(
                of: needle,
                options: options,
                range: NSRange(location: start, length: text.length - start)
            )
            guard found.location != NSNotFound, found.length > 0 else {
                break
            }
            spans.append(TextSpan(start: found.location, length: found.length))
            start = found.location + found.length
        }
        return spans
    }

    private static func whitespaceSpans(of needle: String, in text: NSString) -> [TextSpan] {
        let pattern = needle
            .split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: #"\s+"#)
        guard !pattern.isEmpty else {
            return []
        }
        var spans: [TextSpan] = []
        var start = 0
        while start < text.length {
            let found = text.range(
                of: pattern,
                options: options.union(.regularExpression),
                range: NSRange(location: start, length: text.length - start)
            )
            guard found.location != NSNotFound, found.length > 0 else {
                break
            }
            spans.append(TextSpan(start: found.location, length: found.length))
            start = found.location + found.length
        }
        return spans
    }
}
