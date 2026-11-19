import Foundation

public enum InlineMath {
    public static func looksLikeProse(_ text: String) -> Bool {
        !text.contains(/[\\^_{}=+<>]/) && text.contains(/\p{L}{3,}/)
    }
}
