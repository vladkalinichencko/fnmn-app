import XCTest
@testable import FNMN

final class ConnectionCheckTests: XCTestCase {
    func testAFailedSaveKeepsTheError() {
        XCTAssertEqual(ConnectionCheck.checking.send(.saveFailed("bad address")), .failed("bad address"))
    }

    func testAFailedCheckKeepsTheError() {
        XCTAssertEqual(ConnectionCheck.checking.send(.checkFailed("no answer")), .failed("no answer"))
    }

    func testAPassedCheckIsConnected() {
        XCTAssertEqual(ConnectionCheck.checking.send(.checkPassed), .connected)
    }

    func testEditingAFieldDropsTheLastResult() {
        XCTAssertEqual(ConnectionCheck.connected.send(.edited), .editing)
        XCTAssertEqual(ConnectionCheck.failed("no answer").send(.edited), .editing)
    }
}
