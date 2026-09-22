import Foundation
import Testing
@testable import FNMNCore

@Test func youtubeIDComesFromThePublicAddress() {
    #expect(YouTube.videoID(in: URL(string: "https://youtu.be/abcdefghijk")!) == "abcdefghijk")
    #expect(YouTube.videoID(in: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!) == "abcdefghijk")
    #expect(YouTube.videoID(in: URL(string: "https://www.youtube.com/shorts/abcdefghijk")!) == "abcdefghijk")
    #expect(YouTube.videoID(in: URL(string: "https://example.com/watch?v=abcdefghijk")!) == nil)
}

@Test func youtubePackageKeepsTimedCues() throws {
    let page = """
    ytInitialPlayerResponse = {"videoDetails":{"title":"Fixture talk","author":"Channel"},"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[{"baseUrl":"https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=en","languageCode":"en"}]}}};
    """
    let watch = YouTube.watch(in: page)
    #expect(watch.title == "Fixture talk")
    #expect(watch.author == "Channel")
    #expect(watch.captionBaseURL == "https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=en")

    let cues = YouTube.cues(inTimedText: #"{"events":[{"tStartMs":0,"segs":[{"utf8":"Hello"}]},{"tStartMs":1500,"segs":[{"utf8":"world"}]},{"tStartMs":2000}]}"#)
    let package = YouTube.package(
        videoID: "abcdefghijk",
        sourceURL: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!,
        title: watch.title ?? "",
        author: watch.author,
        cues: cues
    )
    #expect(package.material.id == "youtube:abcdefghijk")
    #expect(package.material.kind == .video)
    #expect(package.body == "Hello\n\nworld")
    let transcripts = package.blocks.filter { $0.kind == .transcript }
    #expect(transcripts.map(\.html) == ["Hello", "world"])
    #expect(transcripts.map(\.startSeconds) == [0, 1.5])
    #expect(package.blocks.first?.mediaURL?.absoluteString == "https://www.youtube.com/embed/abcdefghijk")
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
