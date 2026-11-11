import Foundation
import Testing
@testable import FNMNCore

@Test func youtubeIDComesFromThePublicAddress() throws {
    let url = try #require(Bundle.module.url(forResource: "youtube-urls", withExtension: "json", subdirectory: "Fixtures"))
    let lists = try JSONDecoder().decode(YouTubeAddresses.self, from: Data(contentsOf: url))
    for address in lists.video {
        #expect(YouTube.videoID(in: URL(string: address)!) == "abcdefghijk", "\(address)")
    }
    for address in lists.none {
        #expect(YouTube.videoID(in: URL(string: address)!) == nil, "\(address)")
    }
}

private struct YouTubeAddresses: Decodable {
    let video: [String]
    let none: [String]
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

@Test func onlyTheLowestSectionsStartClosedExceptWhereTheReaderOpens() {
    let document = ReaderDocument(markdown: "# Book\n\nIntro.\n\n# One\n\n## Inner\n\nText.\n\n# Two\n\nMore.", title: "Book")
    #expect(document.lowestHeadings == [3, 5])
    #expect(document.headings(holding: 4) == [2, 3])
    #expect(document.lowestHeadings.subtracting(document.headings(holding: 4)) == [5])
    let ending = ReaderDocument(markdown: "# Book\n\n## Models\n\nText.\n\n## Summary\n\nText.\n\n### More in our Telegram", title: "Book")
    #expect(ending.lowestHeadings == [1, 3])
}

@Test func sectionsReadAboveThePlaceCloseWithTheirSubsections() {
    let document = ReaderDocument(markdown: "# Book\n\nIntro.\n\n# One\n\n## Inner\n\nText.\n\n# Two\n\nMore.", title: "Book")
    #expect(document.headings(endingAbove: 6) == [2, 3])
    #expect(document.headings(endingAbove: 5) == [2, 3])
    #expect(document.headings(endingAbove: 4) == [])
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

@Test func aMaterialMarkedReadHasEveryParagraphRead() {
    let progress = ReadingProgress().applying(.setRead(true, itemID: "a"))
    #expect(progress.isPieceRead(999, of: "a", current: nil))
    #expect(!progress.isPieceRead(0, of: "b", current: nil))
    #expect(!progress.applying(.setRead(false, itemID: "a")).isPieceRead(3, of: "a", current: 1))
}

@Test func startingAMaterialOverLeavesContinueAndKeepsItsFoldedHeadings() {
    let now = Date.now
    let progress = ReadingProgress()
        .applying(.open(itemID: "a"), at: now)
        .applying(.savePosition(.piece(4), itemID: "a", progress: 0.4))
        .applying(.readThrough(piece: 3, itemID: "a"))
        .applying(.fold([1], itemID: "a"))
        .applying(.reset(itemID: "a"))
    #expect(progress.positions["a"] == nil)
    #expect(progress.readThrough["a"] == nil)
    #expect(progress.readings["a"] == nil)
    #expect(progress.folded["a"] == [1])
}
