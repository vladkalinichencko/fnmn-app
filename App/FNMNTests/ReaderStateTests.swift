import FNMNCore
import XCTest
@testable import FNMN

/// The column's handshake: a jump waits for the rows, and a scroll means nothing until it lands.
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

    func testClosingAPlateJumpsBackWithoutHidingTheColumn() {
        var state = ReaderState(place: 2)
        state.shownPlate = 3
        let next = readerReduce(state, .onePlate(false), document: document)
        XCTAssertEqual(next.opening, 3)
        XCTAssertFalse(next.hidesColumn)
        XCTAssertEqual(next.column, .jumping(to: 3, hiding: false))
    }
}
