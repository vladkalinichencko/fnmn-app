import FNMNCore
import SwiftUI

extension AttributedString {
    static func highlighted(_ text: String, spans: [TextSpan], color: Color = .find) -> AttributedString {
        var attributed = AttributedString(text)
        for span in spans {
            guard let found = span.range(in: text) else {
                continue
            }
            let start = text.distance(from: text.startIndex, to: found.lowerBound)
            let end = text.distance(from: text.startIndex, to: found.upperBound)
            let from = attributed.characters.index(attributed.startIndex, offsetBy: start)
            let to = attributed.characters.index(attributed.startIndex, offsetBy: end)
            attributed[from..<to].backgroundColor = color
        }
        return attributed
    }
}
