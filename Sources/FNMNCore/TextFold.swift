import Foundation

public enum TextFold {
    public static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    public static func searchable(_ text: String) -> String {
        collapsed(folded(text))
    }

    static func collapsed(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf16.count)
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace {
                    result.unicodeScalars.append(" ")
                    pendingSpace = false
                }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
