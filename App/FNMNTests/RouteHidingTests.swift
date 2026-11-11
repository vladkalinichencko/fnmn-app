import XCTest
@testable import FNMN

final class RouteHidingTests: XCTestCase {
    func testScreensHideTheTabBarAndListsKeepIt() {
        XCTAssertTrue(Route.item("a").hidesTabBar)
        XCTAssertTrue(Route.item("a", piece: 3).hidesTabBar)
        XCTAssertTrue(Route.album("a").hidesTabBar)
        XCTAssertTrue(Route.source("a").hidesTabBar)
        XCTAssertTrue(Route.group(.types, "article").hidesTabBar)
        XCTAssertFalse(Route.annotations.hidesTabBar)
        XCTAssertFalse(Route.archive.hidesTabBar)
    }

    func testAThreadHidesTheTabBarAndTheSourcesDoNot() {
        XCTAssertTrue(DigestRoute.thread("x/1").hidesTabBar)
        XCTAssertFalse(DigestRoute.sources.hidesTabBar)
    }
}
