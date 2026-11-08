import Foundation

/// Whether a `$…$` pair is a price rather than a formula. The renderer turns the pair into text and the speed
/// reader reads it word by word, and both must answer the same way.
public enum InlineMath {
    /// Prose: no TeX punctuation, and a word of three letters. `$5 and $10` and `$abc$` are prose; `$x^2$`,
    /// `$a + b$` and `$\alpha$` are formulas.
    public static func looksLikeProse(_ text: String) -> Bool {
        !text.contains(/[\\^_{}=+<>]/) && text.contains(/\p{L}{3,}/)
    }
}
