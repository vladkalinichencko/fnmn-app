import XCTest
@testable import FNMNCore

final class WebGenerationTests: XCTestCase {
    func testEveryLoadGetsItsOwnNumber() {
        var generation = WebGeneration()
        XCTAssertEqual(generation.next(), 1)
        XCTAssertEqual(generation.next(), 2)
        XCTAssertEqual(generation.current, 2)
    }

    func testOnlyThePageThatIsLoadedIsHeard() {
        var generation = WebGeneration()
        let first = generation.next()
        XCTAssertTrue(generation.accepts(first))

        let second = generation.next()
        XCTAssertTrue(generation.accepts(second))
        XCTAssertFalse(generation.accepts(first))
    }

    func testAMessageWithNoGenerationIsRefused() {
        var generation = WebGeneration()
        _ = generation.next()
        XCTAssertFalse(generation.accepts(nil))
    }
}
