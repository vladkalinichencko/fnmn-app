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
    #expect(pieces.contains(.text("# Momentum")))
    #expect(pieces.contains(.text("A **ball** on a hill.")))
    #expect(pieces.contains(.image(alt: "slope", path: "assets/slope.gif")))
    #expect(pieces.contains(.video(path: "assets/roll.mp4")))
    #expect(pieces.contains(.interactive(url: URL(string: "https://example.com/post/")!, selector: "#mount")))
    #expect(pieces.contains(.interactive(url: URL(string: "https://videos.example/embed/1")!, selector: nil)))
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
