@testable import FNMNCore
import Testing

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

    @Test func aSingleLetterIsAFormula() {
        #expect(!InlineMath.looksLikeProse("R"))
    }

    @Test func theSpeedReaderReadsAPriceAsWords() {
        let tokens = SpeedText.tokens(in: .text("It costs $5 and $10 today."), at: 0)
        #expect(tokens.map(\.text) == ["It", "costs", "$5", "and", "$10", "today."])
    }

    @Test func theSpeedReaderSkipsAFormula() {
        let tokens = SpeedText.tokens(in: .text("The area is $x^2$ here."), at: 0)
        #expect(tokens.isEmpty)
    }
}
