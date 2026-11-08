import FNMNCore
import SwiftUI
import Textual

/// Textual's Markdown with math, plus the reader's own marks: `==text==` in the source, and the highlights
/// and strikethroughs saved for this paragraph.
struct MarkedMarkdown: MarkupParser {
    let baseURL: URL?
    let marks: [QuoteMark]
    /// The width of the plate's text, when the column is laid out; a picture is never wider.
    var width: CGFloat?
    /// The opening letters of each word are bold.
    var boldsWordStarts = false
    var finds: [TextSpan] = []
    var activeFind: TextSpan?

    func attributedString(for input: String) throws -> AttributedString {
        var text = try Self.parse(input, baseURL: baseURL)
        Self.placePictures(&text, within: width)
        Self.markEqualsHighlights(&text)
        for mark in marks {
            Self.apply(mark, to: &text)
        }
        for find in finds {
            Self.paint(find, .find, in: &text)
        }
        if let activeFind {
            Self.paint(activeFind, .findActive, in: &text)
        }
        if boldsWordStarts { Self.boldWordStarts(&text) }
        return text
    }

    private static func paint(_ span: TextSpan, _ color: Color, in text: inout AttributedString) {
        guard let range = range(of: span, in: text) else {
            return
        }
        text[range].backgroundColor = color
    }

    private static func range(of span: TextSpan, in text: AttributedString) -> Range<AttributedString.Index>? {
        let plain = String(text.characters)
        guard let found = span.range(in: plain) else {
            return nil
        }
        let start = plain.distance(from: plain.startIndex, to: found.lowerBound)
        let end = plain.distance(from: plain.startIndex, to: found.upperBound)
        let from = text.characters.index(text.startIndex, offsetBy: start)
        return from..<text.characters.index(text.startIndex, offsetBy: end)
    }

    /// Sets the opening letters of each word bold, outside code, formulas and pictures. The characters stay as they
    /// are, so a quote is found in the text the same way.
    private static func boldWordStarts(_ text: inout AttributedString) {
        var index = text.startIndex
        var offset = 0
        for range in WordStarts.ranges(in: String(text.characters)) {
            let start = text.characters.index(index, offsetBy: range.lowerBound - offset)
            let end = text.characters.index(start, offsetBy: range.count)
            (index, offset) = (end, range.upperBound)
            for run in text[start..<end].runs where run.textual.attachment == nil {
                let intent = run.inlinePresentationIntent ?? []
                guard !intent.contains(.code) else { continue }
                text[run.range].inlinePresentationIntent = intent.union(.stronglyEmphasized)
            }
        }
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
    /// A display formula also becomes a paragraph of its own, so Textual draws it as a math block: one line
    /// at its own width, which scrolls sideways when it is wider than the plate.
    /// `\[…\]` and `\(…\)` are math too, and a `$…$` inside them would end them early, so those dollars go.
    /// A line break inside `$…$` is a space; a price such as `$5 and $10` is text, not a formula.
    static func protectingMath(_ markdown: String) -> String {
        // Code, a `\\` line break and an escaped dollar come first, so they are passed over whole.
        markdown.replacing(/(?s)(```.+?```|`[^`\n]+`|\\\\|\\\$)|\\\[(.+?)\\\]|\\\((.+?)\\\)|[ \t]*\n?[ \t]*\$\$(.+?)\$\$[ \t]*\n?|\$(?!\$)((?:[^$\n]|\n(?![ \t]*\n))+?)\$/) { match in
            if let code = match.output.1 { return String(code) }
            if let display = match.output.2 ?? match.output.4 {
                return "\n\n$$" + escaped(flattened(String(display))) + "$$\n\n"
            }
            if let inline = match.output.3 ?? match.output.5 {
                let latex = flattened(String(inline))
                if InlineMath.looksLikeProse(latex) {
                    return "\\$" + latex + "\\$"
                }
                // A formula this long would run past the line's end, where a line of text cannot scroll.
                if latex.count > Self.longestInline { return "\n\n$$" + escaped(latex) + "$$\n\n" }
                return "$" + escaped(latex) + "$"
            }
            return String(match.output.0)
        }
        .trimmingCharacters(in: .newlines)
    }

    private static let longestInline = 56

    /// One line, and no dollar signs inside: a formula ends at the first one.
    private static func flattened(_ latex: String) -> String {
        latex.replacing(/\s*\n\s*/, with: " ").replacing(/(\\\$)|\$/) { $0.output.1.map(String.init) ?? "" }
    }

    private static func escaped(_ latex: String) -> String {
        var out = ""
        for character in latex {
            if character.isASCII, character.isPunctuation || character.isSymbol { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// A picture on disk takes its size from the file's header as the paragraph is parsed. Textual's own loader
    /// reads the file only after the paragraph appears, so the paragraph grew by the picture's height and pushed
    /// the column while it scrolled up. Textual first lays the text out before it knows its width, so the picture
    /// is also no wider than the plate's text from the start. Textual draws a picture without taking touches, so the
    /// picture is also a link to its own file, and a tap on it opens it on the whole screen like a link.
    private static func placePictures(_ text: inout AttributedString, within limit: CGFloat?) {
        for run in text.runs {
            guard let url = run.imageURL, url.isFileURL, let size = ImageFiles.headerSize(of: url) else { continue }
            let width = min(size.width, limit ?? size.width)
            let picture = ParagraphPicture(url: url, width: width, height: width * size.height / size.width, description: String(text[run.range].characters))
            text[run.range].textual.attachment = AnyAttachment(picture)
            text[run.range].imageURL = nil
            text[run.range].link = url
        }
    }

    private static func apply(_ mark: QuoteMark, to text: inout AttributedString) {
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

/// A picture inside a paragraph, as wide as the file in pixels or the plate's text, whichever is narrower.
private struct ParagraphPicture: Attachment {
    let url: URL
    let width: CGFloat
    let height: CGFloat
    /// The picture's alt text.
    let description: String

    var body: some View {
        // Its edge is the plate's padding in, like a code block's, so the corners share the plate's center.
        FileImage(url: url, contentMode: .fit)
            .clipShape(.rect(cornerRadius: Tokens.codeRadius, style: .continuous))
            .opensMedia(url)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
        let shown = min(proposal.width ?? width, width)
        return CGSize(width: shown, height: shown * height / width)
    }
}

extension Color {
    static let highlight = Color.accentColor.opacity(0.3)
    static let find = Color.yellow.opacity(0.38)
    static let findActive = Color.orange.opacity(0.6)
}
