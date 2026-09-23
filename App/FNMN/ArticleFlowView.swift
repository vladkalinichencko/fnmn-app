import SwiftUI

struct OutlineEntry: Identifiable, Equatable {
    let piece: Int
    let level: Int
    let title: String
    var id: Int { piece }
}

private enum ReaderDestination: String, Identifiable {
    case outline
    case settings
    var id: String { rawValue }
}

private struct ReaderState {
    var scrollPiece: Int?
    var trackedPiece: Int?
    var destination: ReaderDestination?
    var didRestore = false
}

private enum ReaderAction {
    case scroll(Int?)
    case visible(Int)
    case present(ReaderDestination)
    case dismiss
    case restored
}

private func reduce(_ state: ReaderState, _ action: ReaderAction) -> ReaderState {
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
    case .restored:
        state.didRestore = true
    }
    return state
}

struct MaterialReader: View {
    @Environment(LibraryModel.self) private var library
    let markdown: String
    let file: (String) -> URL?
    let materialID: String
    let title: String
    var sourceURL: URL?
    let outline: [OutlineEntry]
    let startPiece: Int?
    @State private var state = ReaderState()

    var body: some View {
        ReadingSession(
            markdown: markdown,
            file: file,
            materialID: materialID,
            title: title,
            piece: state.scrollPiece,
            onVisiblePiece: { index, count in send(.visible(index), count: count) }
        )
        .dynamicTypeSize(ReaderAppearance.typeSize)
        .background(ReaderAppearance.background ?? Color.clear)
        .navigationTitle(title)
        .toolbar {
            Button("Sections", systemImage: "list.bullet.indent") { send(.present(.outline)) }
                .disabled(outline.isEmpty)
            Button("Text", systemImage: "gearshape") { send(.present(.settings)) }
            if let sourceURL {
                Link("Source", destination: sourceURL)
            }
        }
        .sheet(item: destinationBinding) { destination in
            switch destination {
            case .outline:
                NavigationStack {
                    List(outline) { entry in
                        Button {
                            send(.scroll(entry.piece))
                            send(.dismiss)
                        } label: {
                            Text(entry.title).padding(.leading, CGFloat(max(0, entry.level - 1)) * 12)
                        }
                    }
                    .navigationTitle("Sections")
                }
            case .settings:
                ReaderSettingsForm()
            }
        }
        .task {
            guard !state.didRestore else { return }
            send(.restored)
            if let startPiece { send(.scroll(startPiece)) }
        }
    }

    private var destinationBinding: Binding<ReaderDestination?> {
        Binding(
            get: { state.destination },
            set: { destination in
                if let destination { send(.present(destination)) } else { send(.dismiss) }
            }
        )
    }

    private func send(_ action: ReaderAction, count: Int? = nil) {
        let previous = state.trackedPiece
        state = reduce(state, action)
        guard case let .visible(index) = action, index != previous else { return }
        let total = count ?? ArticleBody.pieces(in: markdown).count
        let progress = total == 0 ? 0 : Double(index + 1) / Double(total)
        Task { await library.save(position: .piece(index), materialID: materialID, progress: progress) }
    }
}

struct ArticleFlowView: View {
    @Environment(LibraryModel.self) private var library
    let package: ImportPackage

    private var markdown: String {
        ArticleBody.readingMarkdown(body: package.body, blocks: package.blocks)
    }

    var body: some View {
        MaterialReader(
            markdown: markdown,
            file: { LibraryFile.articleFile(root: library.storageURL, materialID: package.material.id, path: $0, revision: library.snapshot.articleRevisions[package.material.id]) },
            materialID: package.material.id,
            title: package.material.title,
            sourceURL: package.material.sourceURL,
            outline: ArticleBody.headings(in: markdown).map {
                OutlineEntry(piece: $0.piece, level: $0.level, title: $0.title)
            },
            startPiece: startPiece
        )
    }

    private var startPiece: Int? {
        guard let position = library.snapshot.positions[package.material.id] else { return nil }
        if let piece = position.pieceIndex { return piece }
        guard let block = package.blocks.first(where: { $0.id == position.blockID }),
              let index = package.sections.firstIndex(where: { $0.id == block.sectionID }) else { return nil }
        let headings = ArticleBody.headings(in: markdown)
        guard headings.indices.contains(index) else { return nil }
        return headings[index].piece
    }
}
