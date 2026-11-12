import XCTest
@testable import FNMN

final class ShelfScreenTests: XCTestCase {
    func testTheShelfWaitsForTheLibraryBeforeClaimingItIsEmpty() {
        XCTAssertEqual(ShelfScreen.placeholder(settling: true), .loading)
        XCTAssertEqual(ShelfScreen.placeholder(settling: false), .empty)
    }
}
