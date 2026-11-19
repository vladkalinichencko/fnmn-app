import REEDCore
import XCTest
@testable import REED

final class MarkedMarkdownTests: XCTestCase {
    func testPlainTextIsSafeOffMain() {
        let plain: @Sendable (String, URL?) -> String = MarkedMarkdown.plainText
        XCTAssertEqual(plain("A **bold** move", nil), "A bold move")
    }
}
