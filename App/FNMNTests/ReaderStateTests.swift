import FNMNCore
import XCTest
@testable import FNMN

final class ReaderStateTests: XCTestCase {
    private let document = ReaderDocument(
        markdown: "# Book\n\nIntro.\n\n## One\n\nText one.\n\n## Two\n\nText two.",
        title: "Book"
    )

    func testAScrollIsIgnoredUntilTheFirstJumpLands() {
        var state = ReaderState(place: nil)
        state.column = .jumping(to: 3, hiding: true)
        XCTAssertTrue(state.hidesColumn)
        XCTAssertEqual(state.opening, 3)

        state = readerReduce(state, .scrolled(1), document: document)
        XCTAssertNil(state.scrollID)
        XCTAssertNil(state.place)

        state = readerReduce(state, .opened, document: document)
        XCTAssertEqual(state.column, .laidOut)
        XCTAssertEqual(state.scrollID, 3)
        XCTAssertNil(state.opening)
        XCTAssertFalse(state.hidesColumn)

        state = readerReduce(state, .scrolled(1), document: document)
        XCTAssertEqual(state.scrollID, 1)
        XCTAssertEqual(state.place, 1)
    }

    func testASecondOpenedChangesNothing() {
        var state = ReaderState(place: nil)
        state.scrollID = 4
        XCTAssertEqual(readerReduce(state, .opened, document: document), state)
    }

    func testAFindThatArrivesAfterAnotherQueryIsDropped() {
        var state = readerReduce(ReaderState(place: nil), .find(true), document: document)
        state = readerReduce(state, .findQuery("one"), document: document)
        XCTAssertEqual(state.find?.result, .searching)
        state = readerReduce(state, .findQuery("two"), document: document)

        let late = readerReduce(state, .found([TextMatch(piece: 3, span: TextSpan(start: 1, length: 3))], query: "one"), document: document)
        XCTAssertEqual(late.find?.result, .searching)

        let matches = [TextMatch(piece: 7, span: TextSpan(start: 0, length: 3))]
        let taken = readerReduce(late, .found(matches, query: "two"), document: document)
        XCTAssertEqual(taken.find?.result, .matches(matches, current: 0))
        XCTAssertEqual(taken.find?.current, 0)
    }

    func testAnEmptyQuerySearchesForNothing() {
        var state = readerReduce(ReaderState(place: nil), .find(true), document: document)
        state = readerReduce(state, .findQuery("one"), document: document)
        XCTAssertEqual(state.find?.result, .searching)

        state = readerReduce(state, .findQuery("  "), document: document)
        XCTAssertEqual(state.find?.result, .idle)
        XCTAssertNil(state.find?.current)
    }

    func testTheMatchesAreWalkedInACircle() {
        let matches = [3, 5, 7].map { TextMatch(piece: $0, span: TextSpan(start: 0, length: 2)) }
        var state = readerReduce(ReaderState(place: nil), .find(true), document: document)
        state = readerReduce(state, .findQuery("text"), document: document)
        state = readerReduce(state, .found(matches, query: "text"), document: document)

        state = readerReduce(state, .findStep(-1), document: document)
        XCTAssertEqual(state.find?.current, 2)
        state = readerReduce(state, .findStep(1), document: document)
        XCTAssertEqual(state.find?.current, 0)
        XCTAssertEqual(state.find?.matches.count, 3)
    }

    func testASpeedReadThatArrivesAfterSpeedReadingEndedStillLands() {
        var state = readerReduce(ReaderState(place: 2), .speedReading(true), document: document)
        state.showsLine = true
        state = readerReduce(state, .speedReading(false), document: document)

        let shown = ReadingLine(piece: 5, fraction: 0.5)
        let next = readerReduce(state, .speedRead(shown), document: document)
        XCTAssertEqual(next.place, 5)
        XCTAssertEqual(next.line, shown)
        XCTAssertEqual(next.column, .jumping(to: 5, hiding: false))
    }

    func testTheFieldClosesAndTakesItsMatchesWithIt() {
        var state = readerReduce(ReaderState(place: nil), .find(true), document: document)
        state = readerReduce(state, .findQuery("text"), document: document)
        state = readerReduce(state, .found([TextMatch(piece: 3, span: TextSpan(start: 0, length: 2))], query: "text"), document: document)
        XCTAssertNil(readerReduce(state, .find(false), document: document).find)
    }
}
