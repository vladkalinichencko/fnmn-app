@testable import FNMNCore
import Testing

/// The renderer and the speed reader must agree on which `$…$` pairs are text.
@Suite struct InlineMathTests {
    @Test func aPriceIsProse() {
        #expect(InlineMath.looksLikeProse("5 and 10"))
        #expect(InlineMath.looksLikeProse("abc"))
    }

    @Test func texIsAFormula() {
        #expect(!InlineMath.looksLikeProse("x^2"))
        #expect(!InlineMath.looksLikeProse("a + b"))
        #expect(!InlineMath.looksLikeProse("\\alpha"))
        #expect(!InlineMath.looksLikeProse("{x}"))
    }

    /// A lone letter is a variable, not a price: the rule wants a word of three letters.
    @Test func aSingleLetterIsAFormula() {
        #expect(!InlineMath.looksLikeProse("R"))
    }

    @Test func theSpeedReaderReadsAPriceAsWords() {
        let tokens = SpeedText.tokens(in: .text("It costs $5 and $10 today."), at: 0)
        #expect(!tokens.contains { $0.isStop })
    }

    @Test func theSpeedReaderStopsAtAFormula() {
        let tokens = SpeedText.tokens(in: .text("The area is $x^2$ here."), at: 0)
        #expect(tokens.contains { $0.isStop })
    }
}
