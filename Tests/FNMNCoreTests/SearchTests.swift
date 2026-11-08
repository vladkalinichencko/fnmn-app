import Foundation
import Testing
@testable import FNMNCore

private func package(_ body: String, title: String = "Paper") -> ImportPackage {
    ImportPackage(
        material: Material(id: "article:one", kind: .article, title: title, sourceURL: URL(string: "https://x.org/a")),
        sections: [],
        blocks: [],
        body: body
    )
}

@Test func theBodyKeepsEveryParagraphAtTheBlockTheReaderOpens() {
    let body = "First thought.\n\n## A Heading\n\nSecond thought with a word.\n\n![](assets/a.png)\n"
    let entry = SearchBody(package(body))
    let blocks = ArticleBody.blocks(in: body)
    for paragraph in entry.paragraphs {
        guard case let .text(text) = blocks[paragraph.piece] else {
            Issue.record("a paragraph points at a block that is not text")
            return
        }
        #expect(text == paragraph.markdown)
    }
    #expect(entry.paragraphs.count == 2)
}

@Test func aVideoKeepsItsTranscriptLinesAndTheirSeconds() {
    let video = ImportPackage(
        material: Material(id: "video:one", kind: .video, title: "Talk", sourceURL: URL(string: "https://youtu.be/x")),
        sections: [],
        blocks: [
            Block(id: "t1", sectionID: nil, kind: .transcript, html: "  First line. ", startSeconds: 3),
            Block(id: "t2", sectionID: nil, kind: .transcript, html: "Second line.", startSeconds: 9),
            Block(id: "t3", sectionID: nil, kind: .transcript, html: "   ", startSeconds: 12),
        ]
    )
    let entry = SearchBody(video)
    #expect(entry.cues == [SearchCue(seconds: 3, text: "First line."), SearchCue(seconds: 9, text: "Second line.")])
    #expect(entry.paragraphs.isEmpty)
}

@Test func anExcerptKeepsTheMatchInsideItsWindow() {
    let text = String(repeating: "warm ", count: 80) + "needle" + String(repeating: " cold", count: 80)
    let found = (text as NSString).range(of: "needle")
    let excerpt = SearchExcerpt.around(text, span: TextSpan(start: found.location, length: found.length))
    #expect(excerpt.text.hasPrefix("…"))
    #expect(excerpt.text.hasSuffix("…"))
    #expect(excerpt.text.count < text.count)
    #expect(((excerpt.text as NSString).substring(with: NSRange(location: excerpt.span.start, length: excerpt.span.length))) == "needle")
}

@Test func aShortParagraphShowsWholeWithoutAMark() {
    let excerpt = SearchExcerpt.around("A short line with a needle.", span: TextSpan(start: 19, length: 6))
    #expect(excerpt.text == "A short line with a needle.")
    #expect(excerpt.span == TextSpan(start: 19, length: 6))
    #expect(!excerpt.text.contains("…"))
}

@Test func anExcerptCutsBetweenWords() {
    let text = "one " + String(repeating: "x", count: 200) + " two"
    let excerpt = SearchExcerpt.around(text, span: TextSpan(start: 3, length: 3), limit: 40)
    #expect(!excerpt.text.hasSuffix("x"))
    #expect(excerpt.text.hasPrefix("one"))
}

@Test func theMatchIsWalkedThroughTheTextInOrder() {
    let hits = ReadingSearch.spans(of: "needle", in: "needle and a needle")
    #expect(hits.count == 2)
    #expect(hits.map(\.start) == [0, 13])
}
