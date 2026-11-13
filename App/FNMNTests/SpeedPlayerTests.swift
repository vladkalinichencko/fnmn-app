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

    func testAFormulaShownWholeWaitsForContinue() async {
        let player = await loaded("$$\nx^2\n$$\n\nText after.")
        XCTAssertEqual(player.mode, .paused)
        XCTAssertEqual(player.token?.isStop, true)

        player.play()
        XCTAssertEqual(player.mode, .paused)
    }

    func testAStopWaitsForContinueAndSurvivesAPause() async {
        let player = await loaded("One.\n\n$$\nx^2\n$$\n\nAfter.")
        player.play()
        for _ in 0..<40 where player.mode == .playing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.mode, .stopped)
        XCTAssertEqual(player.token?.isStop, true)
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

    func testTogglingOnAStopContinuesPastIt() async {
        let player = await loaded("$$\nx^2\n$$\n\nText after.")
        XCTAssertEqual(player.token?.isStop, true)

        player.toggle()
        XCTAssertEqual(player.mode, .playing)
        XCTAssertEqual(player.token?.isStop, false)
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

    func testAPlateShownWholeStandsBetweenParagraphs() async {
        let player = await loaded()
        player.play()
        for _ in 0..<40 where player.resting == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.resting, 0)
        for _ in 0..<60 where player.mode != .playing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.mode, .playing)
        player.pause()
    }

    func testPausingDuringThePlateStopsTheWords() async {
        let player = await loaded()
        player.play()
        for _ in 0..<40 where player.resting == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.resting, 0)
        player.pause()
        XCTAssertEqual(player.mode, .paused)
        let frame = player.frame
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(player.frame, frame)
    }

    func testTheParagraphPlateCanWaitForATap() async {
        let player = await loaded()
        player.restMode = .manual
        player.play()
        for _ in 0..<40 where player.resting == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.resting, 0)
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(player.resting, 0)

        player.toggle()
        XCTAssertEqual(player.mode, .playing)
        player.pause()
    }

    func testTheParagraphPlateCanBeSkipped() async {
        let player = await loaded()
        player.restSeconds = 30
        player.play()
        for _ in 0..<40 where player.resting == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.resting, 0)

        player.toggle()
        XCTAssertEqual(player.mode, .playing)
        player.pause()
    }

    func testTheTransportTurnsPlatesWhileOneIsShown() async {
        let player = await loaded("# Doc\n\n## One\n\nAlpha.\n\n## Two\n\nBeta.\n\n## Three\n\nGamma.")
        player.restMode = .manual
        player.play()
        for _ in 0..<40 where player.resting == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.resting, 2)

        player.stepForward()
        XCTAssertEqual(player.previewed, 4)
        player.stepForward()
        XCTAssertEqual(player.previewed, 6)
        player.stepForward()
        XCTAssertEqual(player.previewed, 6)
        player.stepBack()
        XCTAssertEqual(player.previewed, 4)
        player.stepBack()
        XCTAssertEqual(player.previewed, 2)
        player.stepBack()
        XCTAssertEqual(player.previewed, 2)

        player.toggle()
        XCTAssertEqual(player.mode, .playing)
        player.pause()
    }

    func testTheTransportTurnsPlatesAroundAStop() async {
        let player = await loaded("One.\n\n$$\nx^2\n$$\n\nTwo.")
        player.play()
        for _ in 0..<40 where player.mode != .stopped {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.token?.isStop, true)

        player.stepBack()
        XCTAssertEqual(player.previewed, 0)
        player.stepForward()
        XCTAssertEqual(player.previewed, 2)
        player.stepForward()
        XCTAssertEqual(player.previewed, 2)

        player.toggle()
        XCTAssertEqual(player.mode, .playing)
        player.pause()
    }

    func testTheParagraphPlateCanBeOff() async {
        let player = await loaded()
        player.restMode = .off
        player.play()
        var rested = false
        for _ in 0..<100 where player.mode == .playing {
            rested = rested || player.resting != nil
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(rested)
        XCTAssertEqual(player.mode, .ended)
    }
}
