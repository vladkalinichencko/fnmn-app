import Foundation
import Testing
@testable import FNMNCore

@Test func everyMatchIsFoundInTheOrderOfItsParagraphs() {
    let matches = ReadingSearch.matches(of: "model", in: [
        4: "A model of the model.",
        1: "No match here.",
        7: "Model at the top.",
    ])
    #expect(matches.map(\.piece) == [4, 4, 7])
    #expect(matches.map(\.span.start) == [2, 15, 0])
    #expect(matches.map(\.span.length) == [5, 5, 5])
}

@Test func theQueryIgnoresCaseAccentsAndWidth() {
    let spans = ReadingSearch.spans(of: "cafe", in: "Le Café, CAFÉ and ＣＡＦＥ.")
    #expect(spans.count == 3)
    #expect((("Le Café, CAFÉ and ＣＡＦＥ." as NSString).substring(with: NSRange(location: spans[0].start, length: spans[0].length))) == "Café")
}

@Test func aQuerySurroundingSpaceIsNotPartOfIt() {
    #expect(ReadingSearch.matches(of: "  model \n", in: [0: "the model"]).count == 1)
    #expect(ReadingSearch.matches(of: "   ", in: [0: "the model"]).isEmpty)
}

@Test func neighbouringMatchesDoNotOverlap() {
    let spans = ReadingSearch.spans(of: "aa", in: "aaaa")
    #expect(spans.count == 2)
    #expect(spans.map(\.start) == [0, 2])
}

@Test func anEmptyParagraphAndAnEmptyDocumentFindNothing() {
    #expect(ReadingSearch.matches(of: "model", in: [:]).isEmpty)
    #expect(ReadingSearch.matches(of: "model", in: [0: ""]).isEmpty)
}
