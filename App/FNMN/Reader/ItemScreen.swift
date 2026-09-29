import FNMNCore
import SwiftUI

/// Opens a material in its reader: the paragraph reader for articles and books, the player for videos.
struct ItemScreen: View {
    let itemID: String
    let startPiece: Int?
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Group {
            if library.snapshot.articles.contains(where: { $0.material.id == itemID }) {
                ArticleOpener(itemID: itemID, startPiece: startPiece)
            } else if let book = library.snapshot.books.first(where: { $0.id == itemID }) {
                BookReaderView(record: book, startPiece: startPiece)
            } else {
                ContentUnavailableView("This material is no longer in the library", systemImage: "questionmark.folder")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task { library.apply(.open(itemID: itemID)) }
    }
}

private enum ArticleText: Equatable {
    case loading
    case ready(ImportPackage, ReaderDocument?)
    case failed(String)
}

/// Reads an article's or video's package from disk when it opens, and lays an article out into blocks
/// off the main thread; a new revision reads it again.
private struct ArticleOpener: View {
    let itemID: String
    let startPiece: Int?
    @Environment(LibraryModel.self) private var library
    @State private var text = ArticleText.loading

    var body: some View {
        Group {
            switch text {
            case .loading:
                ProgressView()
            case let .failed(message):
                ContentUnavailableView("Couldn’t open this material", systemImage: "doc", description: Text(message))
            case let .ready(package, document):
                if let document {
                    ArticleFlowView(package: package, document: document, startPiece: startPiece)
                } else {
                    VideoReaderView(package: package)
                }
            }
        }
        .task(id: library.snapshot.articleRevisions[itemID]) {
            do {
                let package = try await library.article(itemID)
                text = .ready(package, package.material.kind == .video ? nil : await Self.document(of: package))
            } catch {
                text = .failed(error.localizedDescription)
            }
        }
    }

    @concurrent
    private static func document(of package: ImportPackage) async -> ReaderDocument {
        ReaderDocument(markdown: ArticleBody.readingMarkdown(body: package.body, blocks: package.blocks), title: package.material.title)
    }
}

/// The small source name above the large title at the top of a document.
struct MaterialHeader: View {
    let title: String
    let source: SourceRef?
    @Environment(WindowNavigation.self) private var navigation
    @AppStorage(ReaderAppearance.fontKey) private var readerFont = ReaderFont.system

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let source {
                Button(source.name) { navigation.open(.source(source.name)) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
            Text(title).font(.system(.largeTitle, design: readerFont.design).bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
