import Testing
@testable import FNMNCore

private func words(_ tokens: [SpeedToken]) -> [String] {
    tokens.map { $0.isStop ? "■" : $0.text }
}

@Test func proseReadsAsItsWordsWithoutMarkdown() {
    let tokens = SpeedText.tokens(in: .text("A **bold** [link](https://x.org) and `code`, ==marked== _too_."), at: 4)
    #expect(words(tokens) == ["A", "bold", "link", "and", "code,", "marked", "too."])
    #expect(tokens.allSatisfy { $0.block == 4 })
    #expect(tokens.last?.share == 1)
    #expect(tokens.first?.share == 1.0 / 7)
}

@Test func punctuationSetsThePauseAndStartsTheNextSentence() {
    let tokens = SpeedText.tokens(in: .text("One, two. Three e.g. four: five"), at: 0)
    #expect(tokens.map(\.pause) == [.comma, .sentence, .none, .none, .clause, .paragraph])
    #expect(tokens.map(\.startsSentence) == [true, false, true, false, false, false])
}

@Test func aDashStandingAlonePausesTheWordBeforeIt() {
    let tokens = SpeedText.tokens(in: .text("wait — then go"), at: 0)
    #expect(words(tokens) == ["wait", "then", "go"])
    #expect(tokens[0].pause == .clause)
}

@Test func listItemsReadAsParagraphs() {
    let tokens = SpeedText.tokens(in: .text("- first item\n- second item"), at: 0)
    #expect(words(tokens) == ["first", "item", "second", "item"])
    #expect(tokens[1].pause == .paragraph)
    #expect(tokens[2].startsSentence)
}

@Test func codeFormulasTablesAndPicturesAreStops() {
    let block = DocumentBlock.text("Before it.\n\n```swift\nlet x = 1\n\nlet y = 2\n```\n\n$$x^2$$\n\nAfter $x_1$ here.\n\nPaid $5 and $10 today.")
    let tokens = SpeedText.tokens(in: block, at: 2)
    #expect(words(tokens) == ["Before", "it.", "■", "Paid", "$5", "and", "$10", "today."])
    #expect(tokens[3].startsSentence)
    #expect(words(SpeedText.tokens(in: .text("| a | b |\n|---|---|\n| 1 | 2 |"), at: 0)) == ["■"])
    #expect(words(SpeedText.tokens(in: .image(alt: "", path: "a.png"), at: 0)) == ["■"])
    #expect(SpeedText.tokens(in: .heading(level: 2, title: "Title"), at: 0).isEmpty)
}

@Test func theTextStartsPastWhatTheLineHasRead() {
    let document = ReaderDocument(markdown: "# Doc\n\n## One\n\nOne two three four.\n\nFive six.", title: "Doc")
    let text = SpeedText(document: document, from: ReadingLine(piece: 2, fraction: 0.5))
    #expect(words(text.tokens) == ["three", "four.", "Five", "six."])
    #expect(text.tokens.map(\.block) == [2, 2, 3, 3])
    let fromHeading = SpeedText(document: document, from: ReadingLine(piece: 1, fraction: 0))
    #expect(fromHeading.tokens.count == 6)
}

@Test func aFrameHoldsUpToTwoWordsOfOneSentence() {
    let text = SpeedText(tokens: SpeedText.tokens(in: .text("One two three, four. Five"), at: 0))
    #expect(text.frame(at: 0, words: 2) == 0..<2)
    #expect(text.frame(at: 2, words: 2) == 2..<3)
    #expect(text.frame(at: 3, words: 2) == 3..<4)
    #expect(text.frame(at: 0, words: 1) == 0..<1)
    #expect(text.frame(at: 9, words: 1) == 9..<9)
}

@Test func longWordsAndPunctuationTakeLongerUnlessPausesAreOff() {
    let text = SpeedText(tokens: SpeedText.tokens(in: .text("cat extraordinarily, dog"), at: 0))
    let regular = SpeedPauseProfile(.regular)
    let off = SpeedPauseProfile(.off)
    #expect(text.duration(of: 0..<1, wordsPerMinute: 240, pauses: regular) == 0.25)
    #expect(text.duration(of: 1..<2, wordsPerMinute: 240, pauses: off) == 0.25)
    #expect(text.duration(of: 1..<2, wordsPerMinute: 240, pauses: regular) > 0.25 * 2)
    #expect(text.duration(of: 2..<3, wordsPerMinute: 240, pauses: regular) > text.duration(of: 0..<1, wordsPerMinute: 240, pauses: regular))
}

@Test func minutesLeftCountWordsAndPausesToTheEnd() {
    let text = SpeedText(tokens: SpeedText.tokens(in: .text("a b c d"), at: 0))
    let regular = SpeedPauseProfile(.regular)
    let off = SpeedPauseProfile(.off)
    #expect(text.minutesLeft(from: 0, wordsPerMinute: 2, pauses: off) == 2)
    #expect(text.minutesLeft(from: 2, wordsPerMinute: 2, pauses: off) == 1)
    #expect(text.minutesLeft(from: 4, wordsPerMinute: 2, pauses: regular) == 0)
    #expect(text.minutesLeft(from: 0, wordsPerMinute: 2, pauses: regular) > 2)
}

@Test func eachPauseSettingHoldsBackOnlyItsOwnKind() {
    let tokens = SpeedText.tokens(in: .text("one, two"), at: 0) + SpeedText.tokens(in: .text("three: four"), at: 1)
        + SpeedText.tokens(in: .text("five. Six"), at: 2) + SpeedText.tokens(in: .text("seven 42"), at: 3)
    let text = SpeedText(tokens: tokens)
    for kind in SpeedPauseKind.allCases {
        var quiet = SpeedPauseProfile(.regular)
        quiet.set(.off, for: kind)
        #expect(text.duration(of: 0..<1, wordsPerMinute: 240, pauses: quiet) <= text.duration(of: 0..<1, wordsPerMinute: 240, pauses: SpeedPauseProfile(.regular)))
        #expect(text.duration(of: 1..<2, wordsPerMinute: 240, pauses: quiet) <= text.duration(of: 1..<2, wordsPerMinute: 240, pauses: SpeedPauseProfile(.regular)))
    }
    var commas = SpeedPauseProfile(.off)
    commas.set(.regular, for: .comma)
    #expect(text.duration(of: 0..<1, wordsPerMinute: 240, pauses: commas) > 0.25)
    #expect(text.duration(of: 1..<2, wordsPerMinute: 240, pauses: commas) == 0.25)
    #expect(text.duration(of: 2..<3, wordsPerMinute: 240, pauses: commas) == 0.25)
}

@Test func aColonPausesLongerThanACommaAndShorterThanAFullStop() {
    let colon = SpeedText(tokens: SpeedText.tokens(in: .text("one: two"), at: 0))
    let comma = SpeedText(tokens: SpeedText.tokens(in: .text("one, two"), at: 0))
    let stop = SpeedText(tokens: SpeedText.tokens(in: .text("one. Two"), at: 0))
    let regular = SpeedPauseProfile(.regular)
    let colonBeats = colon.duration(of: 0..<1, wordsPerMinute: 60, pauses: regular)
    let commaBeats = comma.duration(of: 0..<1, wordsPerMinute: 60, pauses: regular)
    let stopBeats = stop.duration(of: 0..<1, wordsPerMinute: 60, pauses: regular)
    #expect(commaBeats < colonBeats)
    #expect(colonBeats < stopBeats)
}

@Test func aProfileIsWrittenAndReadBackWhole() {
    var profile = SpeedPauseProfile(.slight)
    profile.set(.off, for: .numbers)
    profile.set(.regular, for: .longWords)
    let read = SpeedPauseProfile(json: profile.json)
    #expect(read == profile)
    #expect(SpeedPauseProfile(json: "nonsense") == SpeedPauseProfile(.regular))
}

@Test func sentencesStepBackAndForward() {
    let text = SpeedText(tokens: SpeedText.tokens(in: .text("One two. Three four. Five six."), at: 0))
    #expect(text.sentenceStart(before: 3) == 2)
    #expect(text.sentenceStart(before: 2) == 0)
    #expect(text.sentenceStart(before: 0) == 0)
    #expect(text.sentenceStart(after: 0) == 2)
    #expect(text.sentenceStart(after: 2) == 4)
    #expect(text.sentenceStart(after: 4) == nil)
}

@Test func thePivotStandsLeftOfTheMiddle() {
    #expect(SpeedText.pivot(of: "a") == 0)
    #expect(SpeedText.pivot(of: "word") == 1)
    #expect(SpeedText.pivot(of: "reading") == 2)
    #expect(SpeedText.pivot(of: "«reading»") == 3)
    #expect(SpeedText.pivot(of: "comprehension") == 3)
    #expect(SpeedText.pivot(of: "") == 0)
}

@Test func theLastFrameOfABlockEndsIt() {
    let tokens = SpeedText.tokens(in: .text("One two."), at: 0) + SpeedText.tokens(in: .text("Three four."), at: 1)
    let text = SpeedText(tokens: tokens)
    #expect(text.endedBlock(at: 0..<1) == nil)
    #expect(text.endedBlock(at: 1..<2) == 0)
    #expect(text.endedBlock(at: 2..<3) == nil)
    #expect(text.endedBlock(at: 3..<4) == nil)
    #expect(text.endedBlock(at: 4..<4) == nil)
}

@Test func aStopGivenWholeDoesNotEndItsBlock() {
    let tokens = SpeedText.tokens(in: .text("One. $$x^2$$"), at: 0) + SpeedText.tokens(in: .text("Two."), at: 1)
    let text = SpeedText(tokens: tokens)
    #expect(text.endedBlock(at: 0..<2) == nil)
}

@Test func theEndOfTheLastBlockIsNotAStopToRest() {
    let tokens = SpeedText.tokens(in: .text("Only this."), at: 0)
    #expect(SpeedText(tokens: tokens).endedBlock(at: 0..<2) == nil)
}
