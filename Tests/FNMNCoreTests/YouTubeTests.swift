import Foundation
import Testing
@testable import FNMNCore

@Test func youtubeIDComesFromThePublicAddress() {
    #expect(YouTube.videoID(in: URL(string: "https://youtu.be/abcdefghijk")!) == "abcdefghijk")
    #expect(YouTube.videoID(in: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!) == "abcdefghijk")
    #expect(YouTube.videoID(in: URL(string: "https://www.youtube.com/shorts/abcdefghijk")!) == "abcdefghijk")
    #expect(YouTube.videoID(in: URL(string: "https://example.com/watch?v=abcdefghijk")!) == nil)
}

@Test func pinchClosesOneHeadingLayerAtATime() {
    let pieces = ArticleBody.blocks(in: """
    # Chapter

    A paragraph.

    ## Section

    Another paragraph.
    """)
    let once = readingFoldPinchIn(.open, blocks: pieces)
    #expect(visiblePieceIndexes(in: pieces, fold: once).count == 2)
    let twice = readingFoldPinchIn(once, blocks: pieces)
    #expect(visiblePieceIndexes(in: pieces, fold: twice).count == 1)
    let again = readingFoldPinchIn(twice, blocks: pieces)
    #expect(again == twice)
    let opened = readingFoldPinchOut(readingFoldPinchOut(twice, blocks: pieces), blocks: pieces)
    #expect(opened == .open)
    #expect(visiblePieceIndexes(in: pieces, fold: opened).count == pieces.count)
}

@Test func eachPinchTakesTheBlocksOfTheDeepestLevelOffThePageAndTheNextPinchOutBringsThemBack() {
    let pieces = ArticleBody.blocks(in: """
    Before any heading.

    # Chapter

    A paragraph.

    ## Section

    Another paragraph.
    """)
    #expect(readingFoldLeaving(.open, blocks: pieces) == [0, 2, 4])
    let once = readingFoldPinchIn(.open, blocks: pieces)
    #expect(readingFoldLeaving(once, blocks: pieces) == [3])
    let twice = readingFoldPinchIn(once, blocks: pieces)
    #expect(readingFoldLeaving(twice, blocks: pieces).isEmpty)
    #expect(readingFoldArriving(twice, blocks: pieces) == [3])
    #expect(readingFoldArriving(once, blocks: pieces) == [0, 2, 4])
    #expect(readingFoldArriving(.open, blocks: pieces).isEmpty)
}

@Test func aPinchLetGoNearTheStartChangesNothing() {
    let pieces = ArticleBody.blocks(in: "# One\n\nText.\n\n## Two\n\nMore.")
    #expect(readingFoldPinched(.open, scale: 0.95, blocks: pieces) == .open)
    #expect(readingFoldPinched(.open, scale: 0.8, blocks: pieces) == readingFoldPinchIn(.open, blocks: pieces))
    let folded = readingFoldPinchIn(.open, blocks: pieces)
    #expect(readingFoldPinched(folded, scale: 1.2, blocks: pieces) == readingFoldPinchOut(folded, blocks: pieces))
}

@Test func pinchOnAPageWithoutHeadingsStaysOpen() {
    let pieces = ArticleBody.blocks(in: "Only a paragraph.")
    #expect(readingFoldPinchIn(.open, blocks: pieces) == .open)
    #expect(visiblePieceIndexes(in: pieces, fold: .open) == Array(pieces.indices))
}

@Test func readingPlaceStaysOnTheNearestVisibleHeading() {
    #expect(readingPlaceTarget(place: 3, visible: [0, 2]) == 2)
    #expect(readingPlaceTarget(place: 2, visible: [0, 2]) == 2)
    #expect(readingPlaceTarget(place: nil, visible: [0, 2]) == 0)
}
