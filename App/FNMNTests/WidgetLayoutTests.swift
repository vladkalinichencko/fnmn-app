import WidgetKit
import XCTest
@testable import FNMN

final class WidgetLayoutTests: XCTestCase {
    func testContinueShowsOneUntilLargeAndMoreAsItGrows() {
        XCTAssertEqual(WidgetLayout.continueCount(for: .systemSmall), 1)
        XCTAssertEqual(WidgetLayout.continueCount(for: .systemMedium), 1)
        XCTAssertEqual(WidgetLayout.continueCount(for: .systemLarge), 3)
        XCTAssertEqual(WidgetLayout.continueCount(for: .systemExtraLarge), 7)
        XCTAssertEqual(WidgetLayout.continueCount(for: .systemExtraLargePortrait), 7)
    }

    func testDigestIsAGridThatGrowsWithTheWidget() {
        XCTAssertEqual(WidgetLayout.digestCount(for: .systemSmall), 1)
        XCTAssertEqual(WidgetLayout.digestCount(for: .systemMedium), 2)
        XCTAssertEqual(WidgetLayout.digestCount(for: .systemLarge), 4)
        XCTAssertEqual(WidgetLayout.digestCount(for: .systemExtraLarge), 6)
        XCTAssertEqual(WidgetLayout.digestCount(for: .systemExtraLargePortrait), 6)

        XCTAssertEqual(WidgetLayout.digestColumns(for: .systemSmall), 1)
        XCTAssertEqual(WidgetLayout.digestColumns(for: .systemMedium), 2)
        XCTAssertEqual(WidgetLayout.digestColumns(for: .systemLarge), 2)
        XCTAssertEqual(WidgetLayout.digestColumns(for: .systemExtraLarge), 3)
        XCTAssertEqual(WidgetLayout.digestColumns(for: .systemExtraLargePortrait), 3)
    }
}
