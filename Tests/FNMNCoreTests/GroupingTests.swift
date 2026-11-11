@testable import FNMNCore
import Foundation
import Testing

@Suite struct GroupingTests {
    private func package(_ id: String, kind: Material.Kind = .article, source: String?, title: String) -> ImportPackage {
        ImportPackage(
            material: Material(
                id: id,
                kind: kind,
                title: title,
                sourceURL: source.map { URL(string: "https://\($0).example/\(id)")! },
                byline: nil
            ),
            sections: [],
            blocks: [],
            body: "A paragraph long enough to be an excerpt for the tile."
        )
    }

    @Test func aMaterialWithoutASourceIsInNoPublisherGroup() throws {
        var library = LibrarySnapshot()
        try library.importPackage(package("a", source: "alpha", title: "A"), at: Date(timeIntervalSince1970: 1_000))
        try library.importPackage(package("b", kind: .book, source: nil, title: "B"), at: Date(timeIntervalSince1970: 2_000))
        let queries = LibraryQueries(library)
        #expect(queries.groups(by: .publishers, sortedBy: .standard).map(\.name) == ["alpha"])
        #expect(queries.items.count == 2)
    }

    @Test func anUndatedMaterialFallsIntoEarlierAndSortsLast() throws {
        var library = LibrarySnapshot()
        try library.importPackage(package("dated", source: "alpha", title: "Dated"), at: Date(timeIntervalSince1970: 1_000_000_000))
        var undated = ArticleEntry(package("undated", source: "alpha", title: "Undated"))
        library.articles.append(undated)
        let queries = LibraryQueries(library)
        let months = queries.groups(by: .months, sortedBy: .standard)
        #expect(months.map(\.key) == ["2001-09", "0000"])
        #expect(months.last?.name == "Earlier")
        let arranged = LibraryQueries.arrange(queries.items, sortedBy: .title, groupedBy: .months)
        #expect(arranged.map(\.id) == ["2001-09", "0000"])
        #expect(arranged.last?.title == "Earlier")
    }

    @Test func arrangingByPublisherPutsASourcelessItemUnderOther() throws {
        var library = LibrarySnapshot()
        try library.importPackage(package("a", source: "alpha", title: "A"), at: Date(timeIntervalSince1970: 1_000))
        try library.importPackage(package("b", kind: .book, source: nil, title: "B"), at: Date(timeIntervalSince1970: 2_000))
        let queries = LibraryQueries(library)
        let sections = LibraryQueries.arrange(queries.items, sortedBy: .title, groupedBy: .publishers)
        #expect(sections.map(\.title) == ["alpha", "Other"])
        #expect(sections.last?.items.map(\.id) == ["b"])
    }

    @Test func arrangingWithNoGroupingIsOneSection() throws {
        var library = LibrarySnapshot()
        try library.importPackage(package("b", source: "alpha", title: "B"), at: Date(timeIntervalSince1970: 1_000))
        try library.importPackage(package("a", source: "alpha", title: "A"), at: Date(timeIntervalSince1970: 2_000))
        let sections = LibraryQueries.arrange(LibraryQueries(library).items, sortedBy: .title, groupedBy: .none)
        #expect(sections.count == 1)
        #expect(sections.first?.id == "all")
        #expect(sections.first?.title == nil)
        #expect(sections.first?.items.map(\.id) == ["a", "b"])
    }

    @Test func sectionsListThePackagesFoldersThenAnyNewOne() {
        let window = DigestPackage.Window(from: Date(timeIntervalSince1970: 1_000), to: Date(timeIntervalSince1970: 2_000))
        func post(_ id: String, folder: String, at seconds: TimeInterval) -> DigestPackage.Post {
            DigestPackage.Post(
                id: id,
                network: .x,
                author: .init(handle: "ada", name: "Ada"),
                permalink: URL(string: "https://x.com/ada/status/\(id)")!,
                postedAt: Date(timeIntervalSince1970: seconds),
                text: "A post",
                folders: [folder]
            )
        }
        let package = DigestPackage(
            id: "digest-1",
            window: window,
            folders: ["ml", "design"],
            posts: [
                post("1", folder: "ml", at: 1_500),
                post("2", folder: "tech", at: 1_600),
                post("3", folder: "design", at: 1_700),
            ]
        )
        let sections = package.sections(labels: ["3": "design"], hidden: [])
        #expect(sections.map(\.folder) == ["ml", "design", "tech"])
        #expect(sections.first(where: { $0.folder == "ml" })?.posts.map(\.id) == ["1"])
    }

    @Test func aDeclaredFolderWithoutPostsIsNotASection() {
        let window = DigestPackage.Window(from: Date(timeIntervalSince1970: 1_000), to: Date(timeIntervalSince1970: 2_000))
        let post = DigestPackage.Post(
            id: "1", network: .x, author: .init(handle: "ada", name: "Ada"),
            permalink: URL(string: "https://x.com/ada/status/1")!,
            postedAt: Date(timeIntervalSince1970: 1_500), text: "A post", folders: ["ml"]
        )
        let package = DigestPackage(id: "digest-1", window: window, folders: ["ml", "design", "film"], posts: [post])
        #expect(package.sections(labels: [:], hidden: []).map(\.folder) == ["ml"])
    }
}
