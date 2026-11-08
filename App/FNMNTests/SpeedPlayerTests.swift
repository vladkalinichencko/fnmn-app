import FNMNCore
import XCTest
@testable import FNMN

@MainActor
final class SpeedPlayerTests: XCTestCase {
    private func loaded(_ markdown: String = "One two three.\n\nFour five six.\n\nSeven eight nine.") async -> SpeedPlayer {
        let player = SpeedPlayer()
        player.wordsPerMinute = 600
        player.pauses = 0
        let document = ReaderDocument(markdown: markdown, title: "Text")
        await player.load(document, from: ReadingLine(piece: 0, fraction: 0))
        return player
    }

    func testAPlayerWithNoTextDoesNothing() {
        let player = SpeedPlayer()
        XCTAssertEqual(player.mode, .loading)
        XCTAssertFalse(player.hasClock)

        player.play()
        XCTAssertEqual(player.mode, .loading)
        XCTAssertFalse(player.hasClock)
    }

    func testLoadingWaitsAndPlayingRunsWithAClock() async {
        let player = await loaded()
        XCTAssertEqual(player.mode, .paused)
        XCTAssertFalse(player.hasClock)

        player.play()
        XCTAssertEqual(player.mode, .playing)
        XCTAssertTrue(player.hasClock)

        player.pause()
        XCTAssertEqual(player.mode, .paused)
        XCTAssertFalse(player.hasClock)
    }

    func testPlayingTwiceKeepsOneClock() async {
        let player = await loaded()
        player.play()
        player.play()
        XCTAssertEqual(player.mode, .playing)

        player.pause()
        XCTAssertFalse(player.hasClock)
    }

    func testPausingAWaitingPlayerChangesNothing() async {
        let player = await loaded()
        player.pause()
        XCTAssertEqual(player.mode, .paused)
    }

    func testAFormulaShownWholeWaitsForContinue() async {
        let player = await loaded("$$\nx^2\n$$\n\nText after.")
        XCTAssertEqual(player.mode, .paused)
        XCTAssertEqual(player.token?.isStop, true)

        player.play()
        XCTAssertEqual(player.mode, .paused)
        XCTAssertFalse(player.hasClock)
    }

    func testAStopWaitsForContinueAndSurvivesAPause() async {
        let player = await loaded("One.\n\n$$\nx^2\n$$\n\nAfter.")
        player.play()
        for _ in 0..<40 where player.mode == .playing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.mode, .stopped)
        XCTAssertEqual(player.token?.isStop, true)
        XCTAssertFalse(player.hasClock)
        player.pause()
        XCTAssertEqual(player.mode, .stopped)
    }

    func testAJumpAwayFromAStopLeavesTheStopBehind() async {
        let player = await loaded("One.\n\n$$\nx^2\n$$\n\nAfter.")
        player.play()
        for _ in 0..<40 where player.mode == .playing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.mode, .stopped)

        player.sentenceBack()
        XCTAssertEqual(player.mode, .paused)
        XCTAssertEqual(player.token?.isStop, false)
    }

    func testTheWordsFinishAtTheEndAndKeepNoClock() async {
        let player = await loaded("One.")
        player.play()
        XCTAssertEqual(player.mode, .playing)

        for _ in 0..<40 where player.mode == .playing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.mode, .ended)
        XCTAssertFalse(player.hasClock)
    }
}
