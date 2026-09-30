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
            } else {
                ContentUnavailableView("This material is no longer in the library", systemImage: "questionmark.folder")
            }
        }
        .background(HidesTabBarWhenPushed())
        .task { library.apply(.open(itemID: itemID)) }
    }
}

/// The tab bar leaves with the screen below as the reader slides in, and comes back with it on the way back, as
/// UIKit does for a pushed screen. SwiftUI's `.toolbar(.hidden, for: .tabBar)` drops it at once and brings it
/// back only after the pop has ended. The flag is set on the screen the navigation stack pushes, which UIKit
/// reads while it loads that screen, before the slide begins.
private struct HidesTabBarWhenPushed: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Marker { Marker() }
    func updateUIViewController(_: Marker, context: Context) {}

    final class Marker: UIViewController {
        override func willMove(toParent parent: UIViewController?) {
            super.willMove(toParent: parent)
            var screen = parent
            while let current = screen, let above = current.parent {
                if above is UINavigationController {
                    current.hidesBottomBarWhenPushed = true
                    return
                }
                screen = above
            }
        }
    }
}

private enum ArticleText {
    case loading
    /// The phone had let the archive go, so it comes down from iCloud before it can open.
    case downloading
    case article(ReaderCoordinator, sourceURL: URL?)
    case video(VideoCoordinator)
    case failed(String)
}

/// Reads an article's or video's package from disk when it opens, and lays an article out into blocks
/// off the main thread; a new text reads it again.
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
            case .downloading:
                ProgressView("Downloading from iCloud")
            case let .failed(message):
                ContentUnavailableView("Couldn’t open this material", systemImage: "doc", description: Text(message))
            case let .article(reader, sourceURL):
                MaterialReader(reader: reader, sourceURL: sourceURL)
            case let .video(video):
                VideoReaderView(video: video)
            }
        }
        .task(id: library.snapshot.articles.first { $0.material.id == itemID }?.textDigest) {
            let interval = Signposts.library.beginInterval("Open material")
            defer { Signposts.library.endInterval("Open material", interval) }
            if await library.needsDownload(itemID) { text = .downloading }
            do {
                text = try await open()
            } catch {
                text = .failed(error.localizedDescription)
            }
        }
    }

    private func open() async throws -> ArticleText {
        let package = try await library.article(itemID)
        guard package.material.kind != .video else { return .video(VideoCoordinator(package: package, library: library)) }
        guard let baseURL = library.articleFolder(itemID) else { throw LibraryError.cloudFolderMissing }
        let reader = ReaderCoordinator(
            document: await Self.document(of: package),
            materialID: itemID,
            title: package.material.title,
            source: library.snapshot.source(of: itemID),
            baseURL: baseURL,
            place: library.position(of: itemID)?.pieceIndex,
            note: startPiece,
            library: library
        )
        return .article(reader, sourceURL: package.material.sourceURL)
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
