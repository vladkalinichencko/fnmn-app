import FNMNCore
import XCTest
@testable import FNMN

final class PostCardTests: XCTestCase {
    private func post(context: DigestPackage.Post.Context? = nil, comments: [DigestPackage.Post.Comment] = []) -> DigestPackage.Post {
        DigestPackage.Post(
            id: "x/1",
            network: .x,
            author: .init(handle: "handle", name: "Name"),
            permalink: URL(string: "https://x.com/handle/status/1")!,
            postedAt: .now,
            context: context,
            comments: comments
        )
    }

    func testALonePostHasNoThread() {
        XCTAssertFalse(post().hasThread)
    }

    func testContextMakesAThread() {
        let context = DigestPackage.Post.Context(kind: .reply)
        XCTAssertTrue(post(context: context).hasThread)
    }

    func testRepliesMakeAThread() {
        let comment = DigestPackage.Post.Comment(author: "a", text: "hi")
        XCTAssertTrue(post(comments: [comment]).hasThread)
    }
}
