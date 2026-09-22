import Foundation
import Testing
@testable import FNMNCore

@Test func articlePiecesKeepTextImagesVideoAndLiveFigures() throws {
    let markdown = """
    # Momentum

    A **ball** on a hill.

    See ![slope](assets/slope.gif).

    ```fnmn-video
    assets/roll.mp4
    ```

    ```fnmn-interactive
    https://example.com/post/
    #mount
    ```

    ```fnmn-interactive
    https://videos.example/embed/1
    ```
    """
    let pieces = ArticleBody.pieces(in: markdown)
    #expect(pieces.contains(.paragraph([.text("# Momentum")])))
    #expect(pieces.contains(.paragraph([.text("A **ball** on a hill.")])))
    #expect(pieces.contains(.image(alt: "slope", path: "assets/slope.gif")))
    #expect(pieces.contains(.video(path: "assets/roll.mp4")))
    #expect(pieces.contains(.interactive(url: URL(string: "https://example.com/post/")!, selector: "#mount")))
    #expect(pieces.contains(.interactive(url: URL(string: "https://videos.example/embed/1")!, selector: nil)))
}

@Test func displayMathStaysAPieceAndInlineMathStaysInTheParagraph() {
    let pieces = ArticleBody.pieces(in: """
    A ball with $v^2$ rolls.

    $$
    E = mc^2
    $$

    Price is $5 and $6.
    """)
    #expect(pieces.contains(.paragraph([.text("A ball with "), .math("v^2"), .text(" rolls.")])))
    #expect(pieces.contains(.displayMath("E = mc^2")))
    #expect(pieces.contains(.paragraph([.text("Price is $5 and $6.")])))
    #expect(ArticleBody.headingOrdinals(in: ArticleBody.pieces(in: "# One\n\n## Two")) == [1, 2])
    let titled = ArticleBody.pieces(in: "## The $\\sigma$-algebra\n\nNext")
    #expect(ArticleBody.headingOrdinals(in: titled) == [1, nil])
    #expect(ArticleBody.heading(paragraphRuns(titled[0]))?.title == "The $\\sigma$-algebra")
}

private func paragraphRuns(_ piece: ArticlePiece) -> [ArticleRun] {
    guard case let .paragraph(runs) = piece else { return [] }
    return runs
}

@Test func missingBodyBecomesPlainMarkdown() {
    let block = Block(id: "b", sectionID: nil, kind: .heading, html: "<h2>Proof</h2>")
    #expect(ArticleBody.readingMarkdown(body: nil, blocks: [block]) == "## Proof")
    #expect(ArticleBody.readingMarkdown(body: "kept", blocks: [block]) == "kept")
}

@Test func articleFilesStayInsideTheMaterialFolder() throws {
    let root = URL(fileURLWithPath: "/tmp/fnmn-library")
    let file = try #require(LibraryFile.articleFile(root: root, materialID: "article:1", path: "assets/slope.gif"))
    #expect(file.path.hasSuffix("/articles/\(Data("article:1".utf8).base64EncodedString())/assets/slope.gif"))
    #expect(LibraryFile.articleFile(root: root, materialID: "article:1", path: "../state.json") == nil)
}

@Test func packageWithoutBodyStillDecodes() throws {
    let json = """
    {"version":1,"material":{"id":"a","kind":"article","title":"T","sourceURL":"https://example.com"},"sections":[],"blocks":[{"id":"b","sectionID":null,"kind":"paragraph","html":"x","sourceFragment":null,"mediaURL":null,"startSeconds":null}],"folders":[]}
    """
    let package = try JSONDecoder().decode(ImportPackage.self, from: Data(json.utf8))
    #expect(package.body == nil)
    #expect(package.blocks.count == 1)
}
