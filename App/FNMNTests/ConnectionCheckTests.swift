import XCTest
@testable import FNMN

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
}
