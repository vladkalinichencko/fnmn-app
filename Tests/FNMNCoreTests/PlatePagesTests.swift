import Testing
@testable import FNMNCore

private let paper = ReaderDocument(
    markdown: "# Paper\n\n![](assets/cover.png)\n\n## One\n\nFirst\n\n### Deeper\n\nSecond\n\n## Two\n\nThird\n\n## Empty",
    title: "Paper"
)

@Test func platesAreEveryBlockButTheHeadingsAndTheCover() {
    #expect(paper.plates == [3, 5, 7])
}
