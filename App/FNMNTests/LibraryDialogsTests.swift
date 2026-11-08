import XCTest
@testable import FNMN

final class LibraryDialogsTests: XCTestCase {
    func testANewCollectionStartsEmptyAndKeepsWhatIsTyped() {
        let dialog = dialogReduce(.none, .nameAlbum(adding: nil))
        XCTAssertEqual(dialog, .namingAlbum(adding: nil, draft: ""))

        let typed = dialogReduce(dialog, .typeAlbumName("Science"))
        XCTAssertEqual(typed, .namingAlbum(adding: nil, draft: "Science"))

        XCTAssertEqual(dialogReduce(typed, .dismiss), .none)
    }

    func testRenamingKeepsTheOldNameAndTheTypedOneApart() {
        let dialog = dialogReduce(.none, .renameAlbum("Old"))
        XCTAssertEqual(dialog, .renamingAlbum(name: "Old", draft: "Old"))
        XCTAssertEqual(dialogReduce(dialog, .typeAlbumName("New")), .renamingAlbum(name: "Old", draft: "New"))
    }

    func testTypingOutsideAnAlbumDialogChangesNothing() {
        XCTAssertEqual(dialogReduce(.none, .typeAlbumName("X")), .none)
        XCTAssertEqual(dialogReduce(.pickingFile, .typeAlbumName("X")), .pickingFile)
    }
}
