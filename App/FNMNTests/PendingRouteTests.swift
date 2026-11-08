import XCTest
@testable import FNMN

/// A hand-off from outside the app waits for a usable library and opens exactly once.
final class PendingRouteTests: XCTestCase {
    func testALibraryThatIsNotReadyKeepsTheRouteWaiting() {
        let (rest, route) = PendingRoute.continueReading.consume(.needsFolder) {
            .item("one")
        }
        XCTAssertEqual(rest, .continueReading)
        XCTAssertNil(route)
    }

    func testAReadyLibraryTakesTheRouteAndClearsIt() {
        let (rest, route) = PendingRoute.continueReading.consume(.ready) {
            .item("one")
        }
        XCTAssertEqual(rest, .none)
        XCTAssertEqual(route, .item("one"))
    }

    func testTheRouteIsAskedForOnlyOnce() {
        let (rest, _) = PendingRoute.continueReading.consume(.ready) {
            .item("one")
        }
        let second = rest.consume(.ready) {
            XCTFail("nothing is left to open")
            return .item("two")
        }
        XCTAssertEqual(second.0, .none)
        XCTAssertNil(second.1)
    }

    func testNothingToContinueStillClearsTheWait() {
        let (rest, route) = PendingRoute.continueReading.consume(.ready) {
            nil
        }
        XCTAssertEqual(rest, .none)
        XCTAssertNil(route)
    }

    func testASecondHandOffReplacesTheFirst() {
        XCTAssertEqual(PendingRoute.none.arriving(), .continueReading)
        XCTAssertEqual(PendingRoute.continueReading.arriving(), .continueReading)
    }
}
