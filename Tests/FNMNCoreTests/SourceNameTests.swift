@testable import FNMNCore
import Foundation
import Testing

/// A material's publisher is the one the server saw on the page; the catalog's guess is only the fallback.
@Suite struct SourceNameTests {
    private func package(source: PageSource?) -> ImportPackage {
        ImportPackage(
            material: Material(
                id: "article:source",
                kind: .article,
                title: "A post",
                sourceURL: URL(string: "https://blog.example.com/post")!,
                byline: nil,
                source: source
            ),
            sections: [],
            blocks: [],
            body: "A paragraph long enough to be an excerpt for the tile."
        )
    }

    @Test func theServersPublisherWinsOverTheHostGuess() throws {
        var library = LibrarySnapshot()
        let declared = PageSource(name: "The Blog", homepage: URL(string: "https://blog.example.com")!)
        try library.importPackage(package(source: declared), at: Date(timeIntervalSince1970: 1_000))
        let queries = LibraryQueries(library)
        #expect(queries.item("article:source")?.source?.name == "The Blog")
        #expect(library.source(of: "article:source")?.name == "The Blog")
        #expect(queries.groups(by: .publishers, sortedBy: .name).map(\.name) == ["The Blog"])
    }

    @Test func aDeclaredSourceWithoutANameUsesItsHost() throws {
        var library = LibrarySnapshot()
        let declared = PageSource(name: nil, homepage: URL(string: "https://blog.example.com")!)
        try library.importPackage(package(source: declared), at: Date(timeIntervalSince1970: 1_000))
        #expect(LibraryQueries(library).item("article:source")?.source?.name == "example")
    }

    @Test func aPageTheServerDidNotNameFallsBackToItsHost() throws {
        var library = LibrarySnapshot()
        try library.importPackage(package(source: nil), at: Date(timeIntervalSince1970: 1_000))
        #expect(LibraryQueries(library).item("article:source")?.source?.name == "example")
    }
}
