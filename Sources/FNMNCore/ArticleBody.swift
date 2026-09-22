import Foundation

public enum ArticlePiece: Equatable, Sendable {
    case text(String)
    case image(alt: String, path: String)
    case video(path: String)
    case interactive(url: URL, selector: String?)
}

public enum ArticleBody {
    public static func pieces(in markdown: String) -> [ArticlePiece] {
        var pieces: [ArticlePiece] = []
        var rest = markdown[...]
        while let open = rest.range(of: "```") {
            appendText(String(rest[..<open.lowerBound]), to: &pieces)
            rest = rest[open.upperBound...]
            guard let close = rest.range(of: "```") else {
                appendText("```" + rest, to: &pieces)
                return pieces
            }
            appendFence(String(rest[..<close.lowerBound]), to: &pieces)
            rest = rest[close.upperBound...]
        }
        appendText(String(rest), to: &pieces)
        return pieces
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
            pieces.append(.text("```\n\(text)\n```"))
        }
    }

    private static func appendText(_ raw: String, to pieces: inout [ArticlePiece]) {
        for paragraph in raw.components(separatedBy: "\n\n") {
            appendParagraph(paragraph[...], to: &pieces)
        }
    }

    private static func appendParagraph(_ raw: Substring, to pieces: inout [ArticlePiece]) {
        var cursor = raw[...]
        while let marker = cursor.range(of: "![") {
            let before = cursor[..<marker.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty {
                pieces.append(.text(String(before)))
            }
            cursor = cursor[marker.upperBound...]
            guard let altEnd = cursor.firstIndex(of: "]") else {
                pieces.append(.text("![" + cursor))
                return
            }
            let paren = cursor.index(after: altEnd)
            guard paren < cursor.endIndex, cursor[paren] == "(", let pathEnd = cursor[cursor.index(after: paren)...].firstIndex(of: ")") else {
                pieces.append(.text("![" + cursor))
                return
            }
            let alt = String(cursor[..<altEnd])
            let path = String(cursor[cursor.index(after: paren)..<pathEnd])
            pieces.append(.image(alt: alt, path: path))
            cursor = cursor[cursor.index(after: pathEnd)...]
        }
        let tail = cursor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            pieces.append(.text(String(tail)))
        }
    }
}
