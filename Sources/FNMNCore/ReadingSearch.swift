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
}
