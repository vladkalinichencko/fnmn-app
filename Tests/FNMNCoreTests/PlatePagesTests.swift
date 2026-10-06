import Testing
@testable import FNMNCore

private let paper = ReaderDocument(
    markdown: "# Paper\n\n![](assets/cover.png)\n\n## One\n\nFirst\n\n### Deeper\n\nSecond\n\n## Two\n\nThird\n\n## Empty",
    title: "Paper"
)

@Test func platesAreEveryBlockButTheHeadingsAndTheCover() {
    #expect(paper.plates == [3, 5, 7])
}

@Test func aHeadingIsReadAtThePlateAfterItAndTheLastHeadingsAtTheLastPlate() {
    #expect(paper.plate(holding: 0) == 3)
    #expect(paper.plate(holding: 2) == 3)
    #expect(paper.plate(holding: 5) == 5)
    #expect(paper.plate(holding: 6) == 7)
    #expect(paper.plate(holding: 8) == 7)
    #expect(ReaderDocument(markdown: "# Only\n\n## Headings", title: "Only").plate(holding: 0) == nil)
}

@Test func platesTurnOverHeadingsAndStopAtBothEnds() {
    #expect(paper.plate(after: 3) == 5)
    #expect(paper.plate(after: 5) == 7)
    #expect(paper.plate(after: 7) == nil)
    #expect(paper.plate(before: 7) == 5)
    #expect(paper.plate(before: 5) == 3)
    #expect(paper.plate(before: 3) == nil)
}

@Test func aPlateKnowsItsNumberAndItsPlaceInTheContents() {
    #expect(paper.plateNumber(of: 3) == 1)
    #expect(paper.plateNumber(of: 7) == 3)
    #expect(paper.plateNumber(of: 4) == nil)
    #expect(paper.headingPath(of: 5) == [2, 4])
    #expect(paper.headingPath(of: 7) == [6])
}
