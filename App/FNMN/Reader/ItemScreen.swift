import FNMNCore
import SwiftUI

struct ItemScreen: View {
    let itemID: String
    let startPiece: Int?
    var startSeconds: Double? = nil
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Group {
            if library.snapshot.articles.contains(where: { $0.material.id == itemID }) {
                ArticleOpener(itemID: itemID, startPiece: startPiece, startSeconds: startSeconds)
            } else {
                ContentUnavailableView("This item is no longer in the library", systemImage: "questionmark.folder")
            }
        }
        .task { library.apply(.open(itemID: itemID)) }
    }
}

private enum ArticleText {
    case loading
    case article(ReaderCoordinator, sourceURL: URL?)
    case video(VideoCoordinator)
    case failed(String)
}

private struct ArticleOpener: View {
    let itemID: String
    let startPiece: Int?
    var startSeconds: Double?
    @Environment(LibraryModel.self) private var library
    @State private var text = ArticleText.loading
    @AppStorage(ReaderAppearance.lineKey) private var showsLine = false

    var body: some View {
        Group {
            switch text {
            case .loading:
                Loading()
            case let .failed(message):
                ContentUnavailableView("Couldn’t open this item", systemImage: "doc", description: Text(message))
            case let .article(reader, sourceURL):
                MaterialReader(reader: reader, sourceURL: sourceURL)
            case let .video(video):
                VideoReaderView(video: video)
            }
        }
        .task(id: library.snapshot.articles.first { $0.material.id == itemID }?.textDigest) {
            let interval = Signposts.library.beginInterval("Open material")
            defer { Signposts.library.endInterval("Open material", interval) }
            do {
                text = try await open()
            } catch {
                text = .failed(error.localizedDescription)
            }
        }
    }

    private func open() async throws -> ArticleText {
        let package = try await library.article(itemID)
        guard package.material.kind != .video else {
            return .video(VideoCoordinator(package: package, library: library, startSeconds: startSeconds))
        }
        guard let baseURL = library.articleFolder(itemID) else { throw LibraryError.cloudFolderMissing }
        let document = await Self.document(of: package)
        let place = (showsLine ? library.progress.lines[itemID]?.piece : nil)
            ?? library.progress.openingPiece(of: itemID, place: library.position(of: itemID)?.pieceIndex, count: document.blocks.count)
        let reader = ReaderCoordinator(
            document: document,
            materialID: itemID,
            title: package.material.title,
            source: library.snapshot.source(of: itemID),
            baseURL: baseURL,
            kind: package.material.kind,
            place: place,
            note: startPiece,
            showsLine: showsLine,
            library: library,
            plainText: { MarkedMarkdown.plainText($0, baseURL: baseURL) }
        )
        return .article(reader, sourceURL: package.material.sourceURL)
    }

    @concurrent
    private static func document(of package: ImportPackage) async -> ReaderDocument {
        ReaderDocument(markdown: ArticleBody.readingMarkdown(body: package.body, blocks: package.blocks), title: package.material.title)
    }
}

struct MaterialHeader: View {
    let title: String
    let source: SourceRef?
    @Environment(WindowNavigation.self) private var navigation
    @AppStorage(ReaderAppearance.fontKey) private var readerFont = ReaderFont.system

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let source {
                Button(source.name) { navigation.open(.source(source.id)) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
            Text(title)
                .font(readerFont.font(.largeTitle).bold())
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = title }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
