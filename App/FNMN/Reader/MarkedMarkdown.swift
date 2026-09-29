import FNMNCore
import SwiftUI
import Textual

/// Textual's Markdown with math, plus the reader's own marks: `==text==` in the source, and the highlights
/// and strikethroughs saved for this paragraph.
struct MarkedMarkdown: MarkupParser {
    let baseURL: URL?
    let marks: [ParagraphQuoteMark]

    func attributedString(for input: String) throws -> AttributedString {
        var text = try Self.parse(input, baseURL: baseURL)
        Self.markEqualsHighlights(&text)
        for mark in marks {
            Self.apply(mark, to: &text)
        }
        return text
    }

    /// The paragraph's text as the reader shows it; annotation quotes are found in this string.
    static func plainText(_ markdown: String, baseURL: URL?) -> String {
        guard var text = try? parse(markdown, baseURL: baseURL) else { return markdown }
        markEqualsHighlights(&text)
        return String(text.characters)
    }

    private static func parse(_ markdown: String, baseURL: URL?) throws -> AttributedString {
        try AttributedStringMarkdownParser.markdown(baseURL: baseURL, syntaxExtensions: [.math])
            .attributedString(for: protectingMath(markdown))
    }

    /// Markdown runs before the math extension, so it would eat `\,`, turn `_` into emphasis and split a
    /// formula at its line breaks. Escaping punctuation inside `$…$` and `$$…$$` and joining the lines
    /// hands the LaTeX through unchanged.
    /// A display formula also gets hard line breaks around it, so it stands on its own line inside its paragraph.
    static func protectingMath(_ markdown: String) -> String {
        var text = markdown.replacing(/(?s)[ \t]*\n?[ \t]*\$\$(.+?)\$\$[ \t]*\n?|\$(?!\$)([^$\n]+?)\$/) { match in
            if let display = match.output.1 {
                return "\\\n$$" + escaped(String(display).replacing(/\s*\n\s*/, with: " ")) + "$$\\\n"
            }
            return "$" + escaped(match.output.2.map(String.init) ?? "") + "$"
        }
        if text.hasPrefix("\\\n") { text.removeFirst(2) }
        if text.hasSuffix("\\\n") { text.removeLast(2) }
        return text
    }

    private static func escaped(_ latex: String) -> String {
        var out = ""
        for character in latex {
            if character.isASCII, character.isPunctuation || character.isSymbol { out.append("\\") }
            out.append(character)
        }
        return out
    }

    private static func apply(_ mark: ParagraphQuoteMark, to text: inout AttributedString) {
        var searchStart = text.startIndex
        while searchStart < text.endIndex, let found = text[searchStart...].range(of: mark.quote) {
            switch mark.mark {
            case .highlight: text[found].backgroundColor = .highlight
            case .strikethrough: text[found].strikethroughStyle = .single
            }
            searchStart = found.upperBound
        }
    }

    /// `==text==` outside code becomes a highlight and loses its delimiters.
    private static func markEqualsHighlights(_ text: inout AttributedString) {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let open = text[searchStart...].range(of: "=="),
              let close = text[open.upperBound...].range(of: "==") {
            let inside = open.upperBound..<close.lowerBound
            guard !inside.isEmpty, !isCode(text[open]) else {
                searchStart = open.upperBound
                continue
            }
            text[inside].backgroundColor = .highlight
            let resume = text.characters.distance(from: text.startIndex, to: close.lowerBound) - 2
            text.removeSubrange(close)
            text.removeSubrange(open)
            searchStart = text.characters.index(text.startIndex, offsetBy: resume)
        }
    }

    private static func isCode(_ run: AttributedSubstring) -> Bool {
        run.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true }
    }
}

struct ParagraphQuoteMark: Hashable {
    var quote: String
    var mark: TextMark
}

extension Color {
    static let highlight = Color.accentColor.opacity(0.3)
}
