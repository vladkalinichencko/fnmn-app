import Foundation
import Testing
@testable import FNMNCore

@Test func everyWordGetsItsOwnRange() {
    let text = "The model reads one word."
    let spans = WordSpans.spans(in: text)
    #expect(spans.map { (text as NSString).substring(with: NSRange(location: $0.start, length: $0.length)) }
        == ["The", "model", "reads", "one", "word."])
}

@Test func aDashOrStrayMarkIsNotAWord() {
    let text = "wait — then (go)"
    let spans = WordSpans.spans(in: text)
    #expect(spans.map { (text as NSString).substring(with: NSRange(location: $0.start, length: $0.length)) }
        == ["wait", "then", "(go)"])
}

@Test func theWordsAreTheOnesSpeedReadingShows() {
    let text = "One, two: three. Four 42 — five!"
    let spans = WordSpans.spans(in: text)
    let tokens = SpeedText.tokens(in: .text(text), at: 0).filter { !$0.isStop }
    #expect(spans.count == tokens.count)
    #expect(spans.map { (text as NSString).substring(with: NSRange(location: $0.start, length: $0.length)) }
        == tokens.map(\.text))
}

@Test func anEmptyTextHasNoWords() {
    #expect(WordSpans.spans(in: "").isEmpty)
    #expect(WordSpans.spans(in: "   \n\n ").isEmpty)
}
