import XCTest
@testable import FNMN

/// Each page reports which load it belongs to, so a figure replaced mid-load cannot write the new page's phase.
final class WebPageIdentityTests: XCTestCase {
    func testEveryCropMessageReportsItsGeneration() {
        let script = LiveCropWebView.Coordinator.script(selector: ".figure", generation: 7)
        XCTAssertTrue(script.contains("const generation = 7;"), script)
        XCTAssertTrue(script.contains("height: height, generation: generation"), script)
        XCTAssertTrue(script.contains("kind: \"missing\", generation: generation"), script)
    }

    func testThePlayerPageReportsItsGeneration() {
        let page = YouTubeEmbedView.page(
            videoID: "abc",
            origin: URL(string: "https://example.com")!,
            start: 12,
            generation: 3
        )
        XCTAssertTrue(page.contains("payload.generation = 3;"), page)
    }

    func testThePlayerPageStartsAtTheSavedSecond() {
        let page = YouTubeEmbedView.page(
            videoID: "abc",
            origin: URL(string: "https://example.com")!,
            start: 12.7,
            generation: 1
        )
        XCTAssertTrue(page.contains("start=12&"), page)
    }
}
