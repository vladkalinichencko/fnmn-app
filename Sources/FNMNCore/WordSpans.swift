import Foundation

public enum WordSpans {
    public static func spans(in text: String) -> [TextSpan] {
        let text = text as NSString
        var spans: [TextSpan] = []
        var index = 0
        while index < text.length {
            while index < text.length, isSpace(text, index) {
                index += 1
            }
            guard index < text.length else {
                break
            }
            let start = index
            while index < text.length, !isSpace(text, index) {
                index += 1
            }
            let piece = text.substring(with: NSRange(location: start, length: index - start))
            guard piece.contains(where: { $0.isLetter || $0.isNumber }) else {
                continue
            }
            spans.append(TextSpan(start: start, length: index - start))
        }
        return spans
    }

    private static func isSpace(_ text: NSString, _ index: Int) -> Bool {
        Unicode.Scalar(text.character(at: index)).map(CharacterSet.whitespacesAndNewlines.contains) ?? true
    }
}
