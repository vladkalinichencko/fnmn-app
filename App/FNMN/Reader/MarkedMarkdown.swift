import FNMNCore
import SwiftUI
import Textual

struct MarkedMarkdown: MarkupParser {
    let baseURL: URL?
    let marks: [QuoteMark]
    var width: CGFloat?
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

    static func plainText(_ markdown: String, baseURL: URL?) -> String {
        guard var text = try? parse(markdown, baseURL: baseURL) else { return markdown }
        markEqualsHighlights(&text)
        return String(text.characters)
    }

    private static func parse(_ markdown: String, baseURL: URL?) throws -> AttributedString {
        try AttributedStringMarkdownParser.markdown(baseURL: baseURL, syntaxExtensions: [.math])
            .attributedString(for: protectingMath(markdown))
    }

    static func protectingMath(_ markdown: String) -> String {
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
                if latex.count > Self.longestInline { return "\n\n$$" + escaped(latex) + "$$\n\n" }
                return "$" + escaped(latex) + "$"
            }
            return String(match.output.0)
        }
        .trimmingCharacters(in: .newlines)
    }

    private static let longestInline = 56

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

private struct ParagraphPicture: Attachment {
    let url: URL
    let width: CGFloat
    let height: CGFloat
    let description: String

    var body: some View {
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
    static let find = Color.accentColor.opacity(0.4)
    static let findActive = Color.accentColor.opacity(0.8)
}
