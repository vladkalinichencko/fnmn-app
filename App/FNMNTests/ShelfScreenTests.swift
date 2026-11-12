import XCTest
@testable import FNMN

final class ShelfScreenTests: XCTestCase {
    func testTheShelfWaitsForTheLibraryBeforeClaimingItIsEmpty() {
        XCTAssertFalse(ShelfScreen.claimsEmpty(settling: true, empty: true))
        XCTAssertTrue(ShelfScreen.claimsEmpty(settling: false, empty: true))
        XCTAssertFalse(ShelfScreen.claimsEmpty(settling: false, empty: false))
    }
}
