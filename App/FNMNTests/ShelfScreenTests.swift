import XCTest
@testable import FNMN

final class ShelfScreenTests: XCTestCase {
    func testTheShelfWaitsForTheLibraryBeforeClaimingItIsEmpty() {
        XCTAssertEqual(ShelfScreen.phase(hasContent: true, settling: true), .content)
        XCTAssertEqual(ShelfScreen.phase(hasContent: false, settling: true), .settling)
        XCTAssertEqual(ShelfScreen.phase(hasContent: false, settling: false), .empty)
        XCTAssertEqual(ShelfScreen.phase(hasContent: true, settling: false), .content)
    }
}
