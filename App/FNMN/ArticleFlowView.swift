import SwiftUI

private enum ArticleDestination: String, Identifiable {
    case outline
    case settings
    var id: String { rawValue }
}

private struct ArticleReaderState {
    var scrollPiece: Int?
    var trackedPiece: Int?
    var destination: ArticleDestination?
}

private enum ArticleReaderAction {
    case scroll(Int?)
    case visible(Int)
    case present(ArticleDestination)
    case dismiss
}

private func reduce(_ state: ArticleReaderState, _ action: ArticleReaderAction) -> ArticleReaderState {
    var state = state
    switch action {
    case let .scroll(piece):
        state.scrollPiece = piece
        if let piece { state.trackedPiece = piece }
    case let .visible(piece):
        state.trackedPiece = piece
    case let .present(destination):
        state.destination = destination
    case .dismiss:
        state.destination = nil
    }
    return state
}

struct ArticleFlowView: View {
    @Environment(LibraryModel.self) private var library
    let package: ImportPackage
    @State private var state = ArticleReaderState()

    private var markdown: String {
        ArticleBody.readingMarkdown(body: package.body, blocks: package.blocks)
    }

    private var pieces: [ArticlePiece] {
        ArticleBody.pieces(in: markdown)
    }

    var body: some View {
        ReadingSession(
            markdown: markdown,
            file: { LibraryFile.articleFile(root: library.storageURL, materialID: package.material.id, path: $0, revision: library.snapshot.articleRevisions[package.material.id]) },
            materialID: package.material.id,
            title: package.material.title,
            piece: state.scrollPiece,
            onVisiblePiece: { index, count in send(.visible(index), count: count) }
        )
        .dynamicTypeSize(ReaderAppearance.typeSize)
        .background(ReaderAppearance.background ?? Color.clear)
        .navigationTitle(package.material.title)
        .toolbar {
            Button("Sections", systemImage: "list.bullet.indent") { send(.present(.outline)) }
            Button("Text", systemImage: "gearshape") { send(.present(.settings)) }
            Link("Source", destination: package.material.sourceURL)
        }
        .sheet(item: destinationBinding) { destination in
            switch destination {
            case .outline:
                NavigationStack {
                    List(Array(package.sections.enumerated()), id: \.element.id) { index, section in
                        Button {
                            if let piece = pieceIndex(forHeading: index + 1) { send(.scroll(piece)) }
                            send(.dismiss)
                        } label: {
                            Text(section.title).padding(.leading, CGFloat(max(0, section.level - 1)) * 12)
                        }
                    }
                    .navigationTitle("Sections")
                }
            case .settings:
                ReaderSettingsForm()
            }
        }
        .task { restore() }
    }

    private var destinationBinding: Binding<ArticleDestination?> {
        Binding(
            get: { state.destination },
            set: { destination in
                if let destination { send(.present(destination)) } else { send(.dismiss) }
            }
        )
    }

    private func pieceIndex(forHeading ordinal: Int) -> Int? {
        ArticleBody.headingOrdinals(in: pieces).firstIndex(of: ordinal)
    }

    private func restore() {
        guard let position = library.snapshot.positions[package.material.id] else { return }
        if let piece = position.pieceIndex {
            send(.scroll(piece))
            return
        }
        guard let block = package.blocks.first(where: { $0.id == position.blockID }) else { return }
        guard let index = package.sections.firstIndex(where: { $0.id == block.sectionID }) else { return }
        if let piece = pieceIndex(forHeading: index + 1) { send(.scroll(piece)) }
    }

    private func send(_ action: ArticleReaderAction, count: Int? = nil) {
        let previous = state.trackedPiece
        state = reduce(state, action)
        guard case let .visible(index) = action, index != previous else { return }
        let total = count ?? pieces.count
        let progress = total == 0 ? 0 : Double(index + 1) / Double(total)
        Task { await library.save(position: .piece(index), materialID: package.material.id, progress: progress) }
    }
}
