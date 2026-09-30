import Foundation
import Testing
@testable import FNMNCore

@Test func youtubeIDComesFromThePublicAddress() {
    #expect(YouTube.videoID(in: URL(string: "https://youtu.be/abcdefghijk")!) == "abcdefghijk")
    #expect(YouTube.videoID(in: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!) == "abcdefghijk")
    #expect(YouTube.videoID(in: URL(string: "https://www.youtube.com/shorts/abcdefghijk")!) == "abcdefghijk")
    #expect(YouTube.videoID(in: URL(string: "https://example.com/watch?v=abcdefghijk")!) == nil)
}

@Test func aFoldedHeadingHidesItsSectionAndNothingAfterIt() {
    let document = ReaderDocument(markdown: "# Chapter\n\nA paragraph.\n\n## Section\n\nAnother paragraph.\n\n# Next\n\nLast.", title: "Book")
    #expect(document.visibleBlocks(folded: []) == Array(document.blocks.indices))
    #expect(document.visibleBlocks(folded: [0]) == [0, 4, 5])
    #expect(document.visibleBlocks(folded: [2]) == [0, 1, 2, 4, 5])
    #expect(document.visibleBlocks(folded: [0, 2]) == [0, 4, 5])
}

@Test func theCoverAndTheRepeatedTitleAreNeverInTheColumn() {
    let document = ReaderDocument(markdown: "# Book\n\n![](cover.png)\n\n## One\n\nText.", title: "Book")
    #expect(document.visibleBlocks(folded: []) == [2, 3])
}

@Test func onlyAHeadingWithBlocksUnderItCanFold() {
    let document = ReaderDocument(markdown: "# Chapter\n\n## Empty\n\n## Full\n\nText.", title: "Book")
    #expect(!document.holdsBlocks(1))
    #expect(document.holdsBlocks(0))
    #expect(document.holdsBlocks(2))
    #expect(!document.holdsBlocks(3))
}


@Test func readingPlaceStaysOnTheNearestVisibleHeading() {
    #expect(readingPlaceTarget(place: 3, visible: [0, 2]) == 2)
    #expect(readingPlaceTarget(place: 2, visible: [0, 2]) == 2)
    #expect(readingPlaceTarget(place: nil, visible: [0, 2]) == 0)
}

@Test func everySectionWithBlocksUnderItStartsClosedExceptWhereTheReaderOpens() {
    let document = ReaderDocument(markdown: "# Book\n\nIntro.\n\n# One\n\n## Inner\n\nText.\n\n# Two\n\nMore.", title: "Book")
    #expect(document.foldableHeadings == [2, 3, 5])
    #expect(document.headings(holding: 4) == [2, 3])
    #expect(document.foldableHeadings.subtracting(document.headings(holding: 4)) == [5])
}

@Test func foldedHeadingsAreKeptPerMaterialAndForgottenWithItsText() {
    var progress = ReadingProgress().applying(.fold([1, 4], itemID: "a"))
    #expect(progress.folded["a"] == [1, 4])
    progress = progress.applying(.fold([], itemID: "a"))
    #expect(progress.folded["a"] == [])
    #expect(progress.applying(.restart(itemID: "a")).folded["a"] == nil)
    let decoded = try? JSONDecoder().decode(ReadingProgress.self, from: JSONEncoder().encode(progress))
    #expect(decoded == progress)
}
