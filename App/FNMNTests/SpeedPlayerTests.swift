import FNMNCore
import XCTest
@testable import FNMN

@MainActor
final class SpeedPlayerTests: XCTestCase {
    private func loaded(_ markdown: String = "One two three.\n\nFour five six.\n\nSeven eight nine.") async -> SpeedPlayer {
        let player = SpeedPlayer()
        player.wordsPerMinute = 600
        player.pauseProfile = SpeedPauseProfile(.off)
        let document = ReaderDocument(markdown: markdown, title: "Text")
        await player.load(document, from: ReadingLine(piece: 0, fraction: 0))
        return player
    }

    func testAPlayerWithNoTextDoesNothing() {
        let player = SpeedPlayer()
        XCTAssertEqual(player.mode, .loading)

        player.play()
        XCTAssertEqual(player.mode, .loading)
    }

    func testLoadingWaitsAndPlayingRuns() async {
        let player = await loaded()
        XCTAssertEqual(player.mode, .paused)

        player.play()
        XCTAssertEqual(player.mode, .playing)

        player.pause()
        XCTAssertEqual(player.mode, .paused)
    }

    func testPausedWordsStandStill() async {
        let player = await loaded()
        let before = player.frame
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(player.frame, before)
    }

    func testPlayingWordsMoveOn() async {
        let player = await loaded()
        player.play()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertGreaterThan(player.frame.lowerBound, 0)
        player.pause()
    }

    func testPlayingTwiceChangesNothing() async {
        let player = await loaded()
        player.play()
        player.play()
        XCTAssertEqual(player.mode, .playing)
    }

    func testPausingAWaitingPlayerChangesNothing() async {
        let player = await loaded()
        player.pause()
        XCTAssertEqual(player.mode, .paused)
    }

    func testTheSpeedReaderSkipsWhatItCannotSay() async {
        let player = await loaded("$$\nx^2\n$$\n\nText after.")
        XCTAssertEqual(player.mode, .paused)
        XCTAssertEqual(player.token?.text, "Text")

        player.play()
        XCTAssertEqual(player.mode, .playing)
        player.pause()
    }

    func testTheSummaryCountsOnlyWhatCameSinceTheLast() async {
        let player = await loaded()
        player.play()
        try? await Task.sleep(for: .milliseconds(350))
        player.sentenceBack()
        player.pause()
        let first = player.summary(itemID: "text", wordsPerMinute: 600, pauses: SpeedPauseProfile(.off).json)
        XCTAssertGreaterThan(first.words, 0)
        XCTAssertEqual(first.backs, 1)

        let second = player.summary(itemID: "text", wordsPerMinute: 600, pauses: SpeedPauseProfile(.off).json)
        XCTAssertEqual(second.words, 0)
        XCTAssertEqual(second.backs, 0)
    }

    func testTheSummaryCountsShownWordsAndReturns() async {
        let player = await loaded("One two three. Four five six. Seven eight nine.")
        player.play()
        try? await Task.sleep(for: .milliseconds(350))
        player.sentenceBack()
        let summary = player.summary(itemID: "text", wordsPerMinute: 600, pauses: SpeedPauseProfile(.off).json)
        XCTAssertGreaterThan(summary.words, 0)
        XCTAssertEqual(summary.backs, 1)
        XCTAssertEqual(summary.mode, .rsvp)
        XCTAssertLessThanOrEqual(summary.startedAt, summary.endedAt)
        player.pause()
    }

    func testTheWordsFinishAtTheEnd() async {
        let player = await loaded("One.")
        player.play()
        XCTAssertEqual(player.mode, .playing)

        for _ in 0..<40 where player.mode == .playing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.mode, .ended)
    }

    func testTheTransportStepsOneWordAtATime() async {
        let player = await loaded("One two three. Four five six.")
        XCTAssertEqual(player.token?.text, "One")

        player.wordForward()
        XCTAssertEqual(player.token?.text, "two")
        player.wordForward()
        XCTAssertEqual(player.token?.text, "three.")
        player.wordForward()
        XCTAssertEqual(player.token?.text, "Four")

        player.wordBack()
        XCTAssertEqual(player.token?.text, "three.")
        XCTAssertEqual(player.backs, 1)
    }

    func testTheTransportStopsAtTheFirstWord() async {
        let player = await loaded()
        player.wordBack()
        XCTAssertEqual(player.token?.text, "One")
        XCTAssertEqual(player.backs, 0)
    }

    func testTheTransportStepsOverWhatItCannotSay() async {
        let player = await loaded("One.\n\n$$\nx^2\n$$\n\nTwo.")
        player.wordForward()
        XCTAssertEqual(player.token?.text, "Two.")
        XCTAssertEqual(player.mode, .paused)

        player.wordBack()
        XCTAssertEqual(player.token?.text, "One.")
    }

    func testTheTransportKeepsPlaying() async {
        let player = await loaded()
        player.play()
        player.wordForward()
        XCTAssertEqual(player.mode, .playing)
        player.pause()
    }
}
