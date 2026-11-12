import XCTest
import WidgetKit
@testable import FNMN

final class WidgetLayoutTests: XCTestCase {
    func testContinuePlanFillsEachFamily() {
        let small = WidgetLayout.continuePlan(for: .systemSmall)
        XCTAssertFalse(small.featured)
        XCTAssertEqual(small.rows, 1)
        XCTAssertEqual(small.columns, 1)
        XCTAssertEqual(small.itemCount, 1)

        let medium = WidgetLayout.continuePlan(for: .systemMedium)
        XCTAssertFalse(medium.featured)
        XCTAssertEqual(medium.rows, 2)
        XCTAssertEqual(medium.columns, 1)
        XCTAssertEqual(medium.itemCount, 2)

        let large = WidgetLayout.continuePlan(for: .systemLarge)
        XCTAssertTrue(large.featured)
        XCTAssertEqual(large.rows, 2)
        XCTAssertEqual(large.columns, 1)
        XCTAssertEqual(large.itemCount, 3)

        let wide = WidgetLayout.continuePlan(for: .systemExtraLarge)
        XCTAssertTrue(wide.featured)
        XCTAssertEqual(wide.rows, 4)
        XCTAssertEqual(wide.columns, 2)
        XCTAssertEqual(wide.itemCount, 7)

        let portrait = WidgetLayout.continuePlan(for: .systemExtraLargePortrait)
        XCTAssertTrue(portrait.featured)
        XCTAssertEqual(portrait.rows, 5)
        XCTAssertEqual(portrait.columns, 1)
        XCTAssertEqual(portrait.itemCount, 6)
    }

    func testDigestGridFillsEachFamily() {
        XCTAssertEqual(WidgetLayout.digestColumns(for: .systemSmall), 1)
        XCTAssertEqual(WidgetLayout.digestColumns(for: .systemMedium), 2)
        XCTAssertEqual(WidgetLayout.digestColumns(for: .systemLarge), 2)
        XCTAssertEqual(WidgetLayout.digestColumns(for: .systemExtraLarge), 4)
        XCTAssertEqual(WidgetLayout.digestColumns(for: .systemExtraLargePortrait), 2)

        XCTAssertEqual(WidgetLayout.digestRows(for: .systemSmall, postCount: 20), 1)
        XCTAssertEqual(WidgetLayout.digestRows(for: .systemMedium, postCount: 20), 1)
        XCTAssertEqual(WidgetLayout.digestRows(for: .systemLarge, postCount: 20), 2)
        XCTAssertEqual(WidgetLayout.digestRows(for: .systemExtraLarge, postCount: 20), 2)
        XCTAssertEqual(WidgetLayout.digestRows(for: .systemExtraLargePortrait, postCount: 20), 5)
        XCTAssertEqual(WidgetLayout.digestRows(for: .systemLarge, postCount: 3), 2)
        XCTAssertEqual(WidgetLayout.digestRows(for: .systemExtraLarge, postCount: 3), 1)
    }
}
