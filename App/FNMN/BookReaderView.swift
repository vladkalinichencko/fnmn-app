import SwiftUI

private enum BookText: Equatable {
    case loading
    case ready(String)
    case failed(String)
}

private enum BookReaderDestination: String, Identifiable {
    case outline
    case settings
    var id: String { rawValue }
}

private struct BookReaderState {
    var text = BookText.loading
    var scrollPiece: Int?
    var trackedPiece: Int?
    var destination: BookReaderDestination?
}

private enum BookReaderAction {
    case loaded(String)
    case failed(String)
    case scroll(Int?)
    case visible(Int)
    case present(BookReaderDestination)
    case dismiss
}

private func reduce(_ state: BookReaderState, _ action: BookReaderAction) -> BookReaderState {
    var state = state
    switch action {
    case let .loaded(markdown):
        state.text = .ready(markdown)
    case let .failed(message):
        state.text = .failed(message)
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

struct BookReaderView: View {
    @Environment(LibraryModel.self) private var library
    let record: BookRecord
    @State private var state = BookReaderState()
    @State private var highlightPiece: Int?
    @State private var highlightQuote = ""
    @State private var highlightCaption = ""

    var body: some View {
        Group {
            switch state.text {
            case .loading:
                ProgressView()
            case let .failed(message):
                ContentUnavailableView("Couldn’t open the book", systemImage: "book.closed", description: Text(message))
            case let .ready(markdown):
                DocumentColumn(
                    markdown: markdown,
                    file: { LibraryFile.bookFile(root: library.storageURL, directoryName: record.directoryName, path: $0) },
                    piece: state.scrollPiece,
                    highlights: library.snapshot.highlights.filter { $0.materialID == record.id },
                    onVisiblePiece: { index, count in send(.visible(index), count: count) },
                    onHighlight: { piece, quote in
                        highlightPiece = piece
                        highlightQuote = quote
                        highlightCaption = ""
                    }
                )
                .dynamicTypeSize(ReaderAppearance.typeSize)
                .background(ReaderAppearance.background ?? Color.clear)
            }
        }
        .navigationTitle(record.metadata.title)
        .toolbar {
            Button("Sections", systemImage: "list.bullet.indent") { send(.present(.outline)) }
                .disabled(!bookIsOpen)
            Button("Text", systemImage: "gearshape") { send(.present(.settings)) }
        }
        .sheet(item: destinationBinding) { destination in
            switch destination {
            case .outline:
                NavigationStack {
                    List(record.metadata.toc) { entry in
                        Button {
                            if case let .ready(markdown) = state.text, let piece = pieceIndex(forHeading: entry.ordinal, in: markdown) {
                                send(.scroll(piece))
                            }
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
        .alert("Highlight", isPresented: Binding(get: { highlightPiece != nil }, set: { if !$0 { highlightPiece = nil } })) {
            TextField("Caption", text: $highlightCaption)
            Button("Save") {
                guard let piece = highlightPiece else { return }
                let quote = highlightQuote
                let caption = highlightCaption
                highlightPiece = nil
                Task { await library.save(highlightQuote: quote, caption: caption, materialID: record.id, piece: piece) }
            }
            Button("Cancel", role: .cancel) { highlightPiece = nil }
        } message: {
            Text(highlightQuote)
        }
        .task { await open() }
    }

    private var bookIsOpen: Bool {
        if case .ready = state.text { return true }
        return false
    }

    private var destinationBinding: Binding<BookReaderDestination?> {
        Binding(
            get: { state.destination },
            set: { destination in
                if let destination { send(.present(destination)) } else { send(.dismiss) }
            }
        )
    }

    private func open() async {
        let storage = library.storageURL
        let directoryName = record.directoryName
        let contentFile = record.metadata.contentFile
        do {
            let markdown = try await LibraryFile(url: storage).bookText(directoryName: directoryName, contentFile: contentFile)
            send(.loaded(markdown))
            if let position = library.snapshot.positions[record.id] {
                if let piece = position.pieceIndex {
                    send(.scroll(piece))
                } else if let heading = BookCatalog.headingID(in: position), let piece = pieceIndex(forHeading: heading, in: markdown) {
                    send(.scroll(piece))
                }
            }
        } catch {
            send(.failed(error.localizedDescription))
        }
    }

    private func pieceIndex(forHeading ordinal: Int, in markdown: String) -> Int? {
        ArticleBody.headingOrdinals(in: ArticleBody.pieces(in: markdown)).firstIndex(of: ordinal)
    }

    private func send(_ action: BookReaderAction, count: Int? = nil) {
        let previous = state.trackedPiece
        state = reduce(state, action)
        guard case let .visible(index) = action, index != previous else { return }
        let total = count ?? 0
        let progress = total == 0 ? 0 : Double(index + 1) / Double(total)
        Task { await library.save(position: .piece(index), materialID: record.id, progress: progress) }
    }
}
