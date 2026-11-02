@testable import FNMNCore
import Foundation
import Testing

/// Selectors given `among` (the collected materials) answer the same as the ones that collect for themselves.
final class CatalogAlongsideTests {
    private static let library: LibrarySnapshot = {
        var library = LibrarySnapshot()
        for index in 0 ..< 40 {
            let package = ImportPackage(
                material: Material(
                    id: "article:\(index)",
                    kind: .article,
                    title: index % 2 == 0 ? "Article \(index) on \(index % 3) kernels" : "Article \(index)",
                    sourceURL: URL(string: "https://site\(index % 4).example.com/post/\(index)")
                ),
                sections: [],
                blocks: [],
                folders: index < 30 ? ["Album \(index % 3)"] : [],
                body: "Paragraph of article \(index)."
            )
            try! library.importPackage(package, at: Date(timeIntervalSinceReferenceDate: Double(index)))
        }
        let lastFive = library.articles.suffix(5).map(\.material.id)
        library.archived = lastFive
        library.annotations = [
            Annotation(materialID: "article:0", piece: 0, text: "First kernel", updatedAt: Date.distantPast),
            Annotation(materialID: lastFive[0], piece: 0, text: "Archived note", note: "kept", updatedAt: .now),
        ]
        library.albums.append("Empty album")
        return library
    }()

    @Test func collectedListsAnswerAsTheCollectingOnes() throws {
        let library = Self.library
        let collected = library.allItems
        let catalog = collected.filter { !library.isArchived($0.id) }
        let progress = ReadingProgress()

        #expect(library.continueItems(progress, among: catalog) == library.continueItems(progress))
        #expect(library.unsortedItems(among: catalog) == library.unsortedItems)
        #expect(library.albumSummaries(among: catalog) == library.albumSummaries)
        #expect(library.items(inAlbum: "Album 1", among: catalog) == library.items(inAlbum: "Album 1"))
        #expect(library.items(in: .types, key: "article", among: catalog) == library.items(in: .types, key: "article"))
        #expect(try library.items(fromSource: #require(collected[0].source?.id), among: catalog) == library.items(fromSource: #require(collected[0].source?.id)))
        let digest: ([AnnotationGroup]) -> [String: [UUID]] = { Dictionary($0.map { ($0.id, $0.annotations.map(\.id)) }, uniquingKeysWith: { first, _ in first }) }
        #expect(digest(library.annotationGroups(among: collected)) == digest(library.annotationGroups))
        #expect(digest(library.annotationGroups(matching: "kernels", among: collected)) == digest(library.annotationGroups(matching: "kernels")))
        #expect(library.items(matching: "3", among: catalog) == library.items(matching: "3"))
        #expect(try library.groupName(.publishers, key: #require(collected[0].source?.id), among: catalog) == library.groupName(.publishers, key: #require(collected[0].source?.id)))

        for grouping in LibraryGrouping.allCases {
            for sort in GroupSort.allCases {
                #expect(library.groups(by: grouping, sortedBy: sort, progress: progress, among: catalog)
                    == library.groups(by: grouping, sortedBy: sort, progress: progress))
            }
        }

        #expect(!library.items.contains { $0.id == library.annotations[1].materialID })
        #expect(collected.contains { $0.id == library.annotations[1].materialID })
    }
}
