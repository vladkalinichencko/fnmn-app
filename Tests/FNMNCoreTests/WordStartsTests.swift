import Testing
@testable import FNMNCore

@Test func eachWordGetsItsOpeningLettersBold() {
    let text = "A reading line, Читатель."
    let bold = WordStarts.ranges(in: text).map { range in
        String(Array(text)[range])
    }
    #expect(bold == ["A", "rea", "li", "Чита"])
}

@Test func anApostropheOrHyphenInsideAWordKeepsItOneWord() {
    let text = "don't self-paced 'quoted' 2026"
    let bold = WordStarts.ranges(in: text).map { String(Array(text)[$0]) }
    #expect(bold == ["do", "self-", "quo", "20"])
}

@Test func shortWordsGetOneLetterAndLongOnesUnderHalf() {
    #expect(WordStarts.boldLength(of: 1) == 1)
    #expect(WordStarts.boldLength(of: 3) == 1)
    #expect(WordStarts.boldLength(of: 4) == 2)
    #expect(WordStarts.boldLength(of: 10) == 5)
}
