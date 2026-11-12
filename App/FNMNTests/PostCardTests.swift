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

    func testACommentWithoutProfileFieldsStillDecodes() throws {
        let data = Data(#"{"author":"a","text":"hi"}"#.utf8)
        let comment = try JSONDecoder().decode(DigestPackage.Post.Comment.self, from: data)
        XCTAssertNil(comment.handle)
        XCTAssertNil(comment.avatar)
    }

    func testACommentDecodesItsProfile() throws {
        let data = Data(#"{"author":"a","handle":"h","avatar":{"path":"media/a.jpg","width":10,"height":10},"text":"hi"}"#.utf8)
        let comment = try JSONDecoder().decode(DigestPackage.Post.Comment.self, from: data)
        XCTAssertEqual(comment.handle, "h")
        XCTAssertEqual(comment.avatar?.path, "media/a.jpg")
    }
}
