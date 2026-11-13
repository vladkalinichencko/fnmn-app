import Foundation
import Testing
@testable import FNMNCore

private func searchBody(_ paragraphs: [String], id: String) -> SearchBody {
    let package = ImportPackage(
        material: Material(id: id, kind: .article, title: "Paper", sourceURL: URL(string: "https://x.org/a")),
        sections: [],
        blocks: [],
        body: paragraphs.joined(separator: "\n\n")
    )
    return SearchBody(package)
}

private func articleEntry(_ title: String, id: String) -> ArticleEntry {
    ArticleEntry(ImportPackage(
        material: Material(id: id, kind: .article, title: title, sourceURL: URL(string: "https://x.org/a")),
        sections: [],
        blocks: [],
        body: ""
    ))
}

private let identity: @Sendable (String) -> String = { $0 }

struct SearchIndexTests {
    @Test func hitsComeFromEverySourceInTheSourcesOrder() async {
        let bodies = ["article:one": searchBody(["A paragraph about entropy."], id: "article:one")]
        let index = await SearchIndex.load(bodies: bodies, plainText: identity)
        let annotation = Annotation(materialID: "article:one", piece: 0, text: "Entropy", note: "")
        let hits = await index.hits(
            query: "entropy",
            articles: [articleEntry("Entropy in kernels", id: "article:one")],
            annotations: [annotation],
            addedAt: [:]
        )
        #expect(hits.map(\.source) == [.material, .text, .annotation])
    }

    @Test func aTextHitSpansTheWordsTheReaderSees() async {
        let bodies = ["article:one": searchBody(["Some **bold** entropy here."], id: "article:one")]
        let index = await SearchIndex.load(bodies: bodies) { $0.replacingOccurrences(of: "**", with: "") }
        let hits = await index.hits(query: "entropy", articles: [], annotations: [], addedAt: [:])
        let hit = hits.first
        #expect(hit?.source == .text)
        #expect(hit?.piece == 0)
        let plain = "Some bold entropy here."
        let span = hit?.span
        #expect(span.map { (plain as NSString).substring(with: NSRange(location: $0.start, length: $0.length)) } == "entropy")
    }

    @Test func matchingIgnoresCaseAndDiacritics() async {
        let bodies = ["article:one": searchBody(["Café society."], id: "article:one")]
        let index = await SearchIndex.load(bodies: bodies, plainText: identity)
        let hits = await index.hits(query: "CAFE", articles: [], annotations: [], addedAt: [:])
        #expect(hits.count == 1)
    }

    @Test func aTranscriptHitKeepsItsSeconds() async {
        let package = ImportPackage(
            material: Material(id: "video:one", kind: .video, title: "Talk", sourceURL: URL(string: "https://youtu.be/x")),
            sections: [],
            blocks: [Block(id: "t1", sectionID: nil, kind: .transcript, html: "The entropy rises.", startSeconds: 42)]
        )
        let index = await SearchIndex.load(bodies: ["video:one": SearchBody(package)], plainText: identity)
        let hits = await index.hits(query: "entropy", articles: [], annotations: [], addedAt: [:])
        #expect(hits.first?.source == .transcript)
        #expect(hits.first?.seconds == 42)
    }

    @Test func newerMaterialsComeFirstInsideOneSource() async {
        let bodies = [
            "article:old": searchBody(["An entropy of ideas."], id: "article:old"),
            "article:new": searchBody(["An entropy of words."], id: "article:new"),
        ]
        let index = await SearchIndex.load(bodies: bodies, plainText: identity)
        let hits = await index.hits(
            query: "entropy",
            articles: [],
            annotations: [],
            addedAt: ["article:old": Date(timeIntervalSinceReferenceDate: 1), "article:new": Date(timeIntervalSinceReferenceDate: 2)]
        )
        #expect(hits.map(\.itemID) == ["article:new", "article:old"])
    }

    @Test func matchingKeepsWhitespaceExactly() async {
        let bodies = ["article:one": searchBody(["A quick  brown\nfox."], id: "article:one")]
        let index = await SearchIndex.load(bodies: bodies, plainText: identity)
        let exact = await index.hits(query: "quick  brown\nfox", articles: [], annotations: [], addedAt: [:])
        #expect(exact.count == 1)
        let collapsed = await index.hits(query: "quick brown fox", articles: [], annotations: [], addedAt: [:])
        #expect(collapsed.isEmpty)
        let trailing = await index.hits(query: "fox. ", articles: [], annotations: [], addedAt: [:])
        #expect(trailing.isEmpty)
    }

    @Test func markupNeverReachesTheFoldedText() async {
        let bodies = ["article:one": searchBody(["Visible entropy.", "```swift\nhiddenToken()\n```"], id: "article:one")]
        let index = await SearchIndex.load(bodies: bodies) { $0.replacingOccurrences(of: "hiddenToken()", with: "") }
        let markup = await index.hits(query: "hiddentoken", articles: [], annotations: [], addedAt: [:])
        #expect(markup.isEmpty)
        let visible = await index.hits(query: "entropy", articles: [], annotations: [], addedAt: [:])
        #expect(visible.count == 1)
    }

    @Test func anEmptyQueryFindsNothing() async {
        let index = await SearchIndex.load(bodies: [:], plainText: identity)
        let hits = await index.hits(query: "   ", articles: [articleEntry("Entropy", id: "article:one")], annotations: [], addedAt: [:])
        #expect(hits.isEmpty)
    }

    @Test func theComputationRunsOffTheMainThread() async {
        let bodies = ["article:one": searchBody(["An entropy of ideas."], id: "article:one")]
        let index = await SearchIndex.load(bodies: bodies) { text in
            Thread.isMainThread ? "main" : text
        }
        let offMain = await index.hits(query: "entropy", articles: [], annotations: [], addedAt: [:])
        #expect(offMain.count == 1)
    }

    @Test func hitsStreamAsTheyAreFound() async {
        let bodies = [
            "article:one": searchBody(["An entropy of ideas."], id: "article:one"),
            "article:two": searchBody(["An entropy of words."], id: "article:two"),
        ]
        let index = await SearchIndex.load(bodies: bodies, plainText: identity)
        var yields: [[SearchHit]] = []
        let found = await index.hits(
            query: "entropy",
            articles: [articleEntry("Entropy in kernels", id: "article:one")],
            annotations: [],
            addedAt: [:]
        ) { yields.append($0) }
        #expect(yields.count >= 2)
        #expect(yields.first?.first?.source == .material)
        #expect(Set(yields.flatMap(\.self).map(\.id)) == Set(found.map(\.id)))
    }

    @Test func hitsOverCollectedBodiesFitTheFrameBudget() async {
        let bodies = Dictionary(uniqueKeysWithValues: (0 ..< 1500).map { index in
            ("article:\(index)", searchBody((1 ... 40).map { $0 == 20 ? "Paragraph \($0) about entropy." : "Paragraph \($0) about kernels." }, id: "article:\(index)"))
        })
        let index = await SearchIndex.load(bodies: bodies, plainText: identity)
        var best = Double.infinity
        for _ in 0 ..< 10 {
            let start = ContinuousClock.now
            _ = await index.hits(query: "entropy", articles: [], annotations: [], addedAt: [:])
            best = min(best, Double((ContinuousClock.now - start) / .milliseconds(1)))
        }
        #expect(best < 120, "hits over the collected bodies took \(best) ms at best")
    }
}
