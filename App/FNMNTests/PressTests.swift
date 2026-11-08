import XCTest
@testable import FNMN

final class PressTests: XCTestCase {
    func testARestingPressWhilePlayingStartsTheWordsAgainOnLift() {
        var press = Press()
        press.land()
        XCTAssertTrue(press.hold(playing: true))
        XCTAssertTrue(press.isHolding)
        XCTAssertTrue(press.lift())
        XCTAssertEqual(press.phase, .idle)
    }

    func testARestingPressWhilePausedLeavesTheWordsWaiting() {
        var press = Press()
        press.land()
        XCTAssertTrue(press.hold(playing: false))
        XCTAssertFalse(press.lift())
        XCTAssertEqual(press.phase, .idle)
    }

    func testAFingerThatLiftedBeforeTheTimerLeavesNothingBehind() {
        var press = Press()
        press.land()
        XCTAssertFalse(press.lift())
        XCTAssertFalse(press.hold(playing: true))
        XCTAssertEqual(press.phase, .idle)
    }

    func testASecondFingerChangesNothing() {
        var press = Press()
        press.land()
        press.land()
        XCTAssertEqual(press.phase, .down)
        XCTAssertTrue(press.hold(playing: true))
        press.land()
        XCTAssertEqual(press.phase, .holding)
    }

    func testATapNeverBecomesAHold() {
        var press = Press()
        press.land()
        XCTAssertFalse(press.isHolding)
        press.lift()
        XCTAssertFalse(press.isHolding)
    }
}
