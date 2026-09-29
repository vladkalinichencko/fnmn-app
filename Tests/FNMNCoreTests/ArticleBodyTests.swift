import Foundation
import Testing
@testable import FNMNCore

@Test func blocksKeepTextImagesVideoAndLiveFigures() throws {
    let markdown = """
    # Momentum

    A **ball** on a hill.

    ![slope](assets/slope.gif)

    ```fnmn-video
    assets/roll.mp4
    ```

    ```fnmn-interactive
    https://example.com/post/
    #mount
    ```

    ```swift

    let x = 1
    ```
    """
    #expect(ArticleBody.blocks(in: markdown) == [
        .heading(level: 1, title: "Momentum"),
        .text("A **ball** on a hill.\n\n![slope](assets/slope.gif)"),
        .video(path: "assets/roll.mp4"),
        .interactive(url: URL(string: "https://example.com/post/")!, selector: "#mount"),
        .text("```swift\n\nlet x = 1\n```"),
    ])
}

@Test func picturesAndCodeJoinTheirParagraphAndOnlyTheOpeningPictureStandsAlone() {
    let blocks = ArticleBody.blocks(in: """
    ![cover](assets/cover.png)

    # Title

    First paragraph.

    ```python
    print(1)
    ```

    ## Section

    ![chart](assets/chart.png)

    Explained here.
    """)
    #expect(blocks == [
        .image(alt: "cover", path: "assets/cover.png"),
        .heading(level: 1, title: "Title"),
        .text("First paragraph.\n\n```python\nprint(1)\n```"),
        .heading(level: 2, title: "Section"),
        .text("![chart](assets/chart.png)\n\nExplained here."),
    ])
}

@Test func aFormulaOrPictureOnItsOwnLineStaysInsideTheParagraph() {
    let blocks = ArticleBody.blocks(in: """
    A function
    $$
    f(x)

    = 1
    $$
    where x is the input, drawn as
    ![curve](assets/c.png)
    ## Next
    Text
    """)
    #expect(blocks == [
        .text("A function\n$$\nf(x)\n\n= 1\n$$\nwhere x is the input, drawn as\n![curve](assets/c.png)"),
        .heading(level: 2, title: "Next"),
        .text("Text"),
    ])
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

@Test func readerDocumentFindsTheRepeatedTitleTheCoverAndWhatEachHeadingHolds() {
    let document = ReaderDocument(
        markdown: "# Paper\n\n![](assets/cover.png)\n\n## One\n\nFirst\n\n### Deeper\n\nSecond\n\n## Two\n\nThird",
        title: "Paper"
    )
    #expect(document.repeatedTitle == 0)
    #expect(document.lead == 1)
    #expect(document.sections[2] == HeadingSection(size: 2, end: 6))
    #expect(document.sections[4] == HeadingSection(size: 1, end: 6))
    #expect(document.sections[6] == HeadingSection(size: 1, end: 8))
}

@Test func packageWithoutBodyStillDecodes() throws {
    let json = """
    {"version":1,"material":{"id":"a","kind":"article","title":"T","sourceURL":"https://example.com"},"sections":[],"blocks":[{"id":"b","sectionID":null,"kind":"paragraph","html":"x","sourceFragment":null,"mediaURL":null,"startSeconds":null}],"folders":[]}
    """
    let package = try JSONDecoder().decode(ImportPackage.self, from: Data(json.utf8))
    #expect(package.body == nil)
    #expect(package.blocks.count == 1)
}
