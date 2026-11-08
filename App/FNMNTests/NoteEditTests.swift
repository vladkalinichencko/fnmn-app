import XCTest
@testable import FNMN

final class NoteEditTests: XCTestCase {
    func testAClosedNoteTakesWhatTheStoreHas() {
        var note = NoteEdit(saved: "first")
        note.arrived("second")
        XCTAssertEqual(note.draft, "second")
        XCTAssertEqual(note.saved, "second")
    }

    func testAnOpenNoteKeepsItsDraftWhenAnotherDeviceWrites() {
        var note = NoteEdit(saved: "first")
        note.begin()
        note.type("mine")
        note.arrived("theirs")
        XCTAssertEqual(note.draft, "mine")
        XCTAssertEqual(note.saved, "first")
    }

    func testAnUntouchedFieldTakesTheIncomingNote() {
        var note = NoteEdit(saved: "first")
        note.begin()
        note.arrived("theirs")
        XCTAssertEqual(note.draft, "theirs")
        XCTAssertEqual(note.saved, "theirs")
    }

    func testClosingSavesTheDraftOnce() {
        var note = NoteEdit(saved: "first")
        note.begin()
        note.type("mine")
        XCTAssertEqual(note.finish(), "mine")
        XCTAssertEqual(note.saved, "mine")
        XCTAssertNil(note.finish())
    }

    func testClosingAnUntouchedFieldSavesNothing() {
        var note = NoteEdit(saved: "first")
        note.begin()
        XCTAssertNil(note.finish())
    }

    func testLeavingWithTheFieldOpenKeepsTheTextAndAClosedNoteSavesNothing() {
        var open = NoteEdit(saved: "first")
        open.begin()
        open.type("mine")
        XCTAssertEqual(open.abandon(), "mine")
        XCTAssertNil(open.abandon())

        var closed = NoteEdit(saved: "first")
        closed.arrived("theirs")
        XCTAssertNil(closed.abandon())
    }
}
