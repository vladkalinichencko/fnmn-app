import FNMNCore
import SwiftUI

private struct ReaderState {
    var scrollPiece: Int?
    var trackedPiece: Int?
    var didRestore = false
}

private enum ReaderAction {
    case scroll(Int)
    case visible(Int)
    case restored
}

private func reduce(_ state: ReaderState, _ action: ReaderAction) -> ReaderState {
    var state = state
    switch action {
    case let .scroll(piece):
        state.scrollPiece = piece
        state.trackedPiece = piece
    case let .visible(piece):
        state.trackedPiece = piece
    case .restored:
        state.didRestore = true
    }
    return state
}

/// Reads an article or a book as one column of paragraphs and keeps the place on the paragraph at the top.
struct MaterialReader: View {
    @Environment(LibraryModel.self) private var library
    let markdown: String
    let baseURL: URL
    let materialID: String
    let header: MaterialHeader
    var sourceURL: URL?
    let startPiece: Int?
    @State private var state = ReaderState()

    var body: some View {
        ReadingSession(
            markdown: markdown,
            materialID: materialID,
            header: header,
            baseURL: baseURL,
            piece: state.scrollPiece,
            onVisiblePiece: { index, count in send(.visible(index), count: count) }
        )
        .modifier(ReaderAppearanceModifier())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ReaderMenu(sourceURL: sourceURL) }
        .task {
            guard !state.didRestore else { return }
            send(.restored)
            if let piece = startPiece ?? library.position(of: materialID)?.pieceIndex { send(.scroll(piece)) }
        }
        .onDisappear { Task { await library.saveProgress() } }
    }

    private func send(_ action: ReaderAction, count: Int? = nil) {
        let previous = state.trackedPiece
        state = reduce(state, action)
        guard case let .visible(index) = action, index != previous else { return }
        let total = count ?? ArticleBody.blocks(in: markdown).count
        let progress = total == 0 ? 0 : Double(index + 1) / Double(total)
        library.apply(.savePosition(.piece(index), itemID: materialID, progress: progress))
    }
}

struct ArticleFlowView: View {
    @Environment(LibraryModel.self) private var library
    let package: ImportPackage
    let startPiece: Int?

    var body: some View {
        let id = package.material.id
        MaterialReader(
            markdown: ArticleBody.readingMarkdown(body: package.body, blocks: package.blocks),
            baseURL: library.articleFolder(id),
            materialID: id,
            header: MaterialHeader(title: package.material.title, source: library.snapshot.source(of: id)),
            sourceURL: package.material.sourceURL,
            startPiece: startPiece
        )
    }
}
