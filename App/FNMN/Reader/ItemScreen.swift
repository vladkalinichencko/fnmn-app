import FNMNCore
import SwiftUI

/// Opens a material in its reader: the paragraph reader for articles and books, the player for videos.
struct ItemScreen: View {
    let itemID: String
    let startPiece: Int?
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Group {
            if let package = library.snapshot.packages.first(where: { $0.material.id == itemID }) {
                if package.material.kind == .video {
                    VideoReaderView(package: package)
                } else {
                    ArticleFlowView(package: package, startPiece: startPiece)
                }
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
