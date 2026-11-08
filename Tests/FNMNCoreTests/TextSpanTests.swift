import Foundation
import Testing
@testable import FNMNCore

@Test func aSpanFindsItsCharacters() {
    let text = "Le Café, CAFÉ."
    let spans = ReadingSearch.spans(of: "café", in: text)
    #expect(spans.count == 2)
    #expect(spans.compactMap { $0.range(in: text) }.map { String(text[$0]) } == ["Café", "CAFÉ"])
}

@Test func aSpanPastTheEndFindsNothing() {
    let text = "short"
    #expect(TextSpan(start: 3, length: 20).range(in: text) == nil)
    #expect(TextSpan(start: 20, length: 1).range(in: text) == nil)
}

@Test func aSpanOnACharacterBoundaryKeepsTheCharacterWhole() {
    let text = "e\u{301}te\u{301}"
    let spans = ReadingSearch.spans(of: "été", in: text)
    #expect(spans.count == 1)
    #expect(spans.first?.range(in: text).map { String(text[$0]) } == "e\u{301}te\u{301}")
}
