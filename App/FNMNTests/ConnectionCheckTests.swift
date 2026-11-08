import XCTest
@testable import FNMN

/// Only a failed save leaves the address and token unwritten; everything after the save has them stored.
final class ConnectionCheckTests: XCTestCase {
    func testAFailedSaveSaysNothingWasStored() {
        XCTAssertEqual(ConnectionCheck.checking.send(.saveFailed("bad address")), .failed("bad address", saved: false))
    }

    func testAFailedCheckSaysTheAddressWasStored() {
        XCTAssertEqual(ConnectionCheck.checking.send(.checkFailed("no answer")), .failed("no answer", saved: true))
    }

    func testAPassedCheckIsConnected() {
        XCTAssertEqual(ConnectionCheck.checking.send(.checkPassed), .connected)
    }

    func testEditingAFieldDropsTheLastResult() {
        XCTAssertEqual(ConnectionCheck.connected.send(.edited), .editing)
        XCTAssertEqual(ConnectionCheck.failed("no answer", saved: true).send(.edited), .editing)
    }

    func testSavingIsDisabledOnlyWhileTheCheckRuns() {
        XCTAssertTrue(ConnectionCheck.checking.isChecking)
        XCTAssertFalse(ConnectionCheck.failed("no answer", saved: true).isChecking)
    }
}
