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
    let pieces = ArticleBody.pieces(in: """
    # Chapter

    A paragraph.

    ## Section

    Another paragraph.
    """)
    let once = readingFoldPinchIn(.open, pieces: pieces)
    #expect(visiblePieceIndexes(in: pieces, fold: once).count == 2)
    let twice = readingFoldPinchIn(once, pieces: pieces)
    #expect(visiblePieceIndexes(in: pieces, fold: twice).count == 1)
    let again = readingFoldPinchIn(twice, pieces: pieces)
    #expect(again == twice)
    let opened = readingFoldPinchOut(readingFoldPinchOut(twice, pieces: pieces), pieces: pieces)
    #expect(opened == .open)
    #expect(visiblePieceIndexes(in: pieces, fold: opened).count == pieces.count)
}

@Test func pinchOnAPageWithoutHeadingsStaysOpen() {
    let pieces = ArticleBody.pieces(in: "Only a paragraph.")
    #expect(readingFoldPinchIn(.open, pieces: pieces) == .open)
    #expect(visiblePieceIndexes(in: pieces, fold: .open) == Array(pieces.indices))
}

@Test func readingPlaceStaysOnTheNearestVisibleHeading() {
    #expect(readingPlaceTarget(place: 3, visible: [0, 2]) == 2)
    #expect(readingPlaceTarget(place: 2, visible: [0, 2]) == 2)
    #expect(readingPlaceTarget(place: nil, visible: [0, 2]) == 0)
}
