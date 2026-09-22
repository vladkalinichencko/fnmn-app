import SwiftUI

private enum ArticleDestination: String, Identifiable {
    case outline
    case note
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
    @State private var highlightPiece: Int?
    @State private var highlightQuote = ""
    @State private var highlightCaption = ""

    private var markdown: String {
        ArticleBody.readingMarkdown(body: package.body, blocks: package.blocks)
    }

    private var pieces: [ArticlePiece] {
        ArticleBody.pieces(in: markdown)
    }

    var body: some View {
        DocumentColumn(
            markdown: markdown,
            file: { LibraryFile.articleFile(root: library.storageURL, materialID: package.material.id, path: $0) },
            piece: state.scrollPiece,
            highlights: library.snapshot.highlights.filter { $0.materialID == package.material.id },
            onVisiblePiece: { index, count in send(.visible(index), count: count) },
            onHighlight: { piece, quote in
                highlightPiece = piece
                highlightQuote = quote
                highlightCaption = ""
            }
        )
        .dynamicTypeSize(ReaderAppearance.typeSize)
        .background(ReaderAppearance.background ?? Color.clear)
        .navigationTitle(package.material.title)
        .toolbar {
            Button("Sections", systemImage: "list.bullet.indent") { send(.present(.outline)) }
            Button(currentNote == nil ? "Add note" : "Edit note", systemImage: "note.text.badge.plus") { send(.present(.note)) }
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
            case .note:
                if let block = noteBlock {
                    NoteEditor(package: package, block: block, initialText: currentNote?.text ?? "")
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
                Task { await library.save(highlightQuote: quote, caption: caption, materialID: package.material.id, piece: piece) }
            }
            Button("Cancel", role: .cancel) { highlightPiece = nil }
        } message: {
            Text(highlightQuote)
        }
        .task { restore() }
    }

    private var noteBlock: Block? {
        if let heading = headingOrdinal, package.sections.indices.contains(heading - 1) {
            let section = package.sections[heading - 1]
            if let block = package.blocks.first(where: { $0.id == section.firstBlockID }) {
                return block
            }
        }
        return package.blocks.first
    }

    private var currentNote: Note? {
        guard let blockID = noteBlock?.id else { return nil }
        return library.snapshot.notes.first { $0.materialID == package.material.id && $0.blockID == blockID }
    }

    private var destinationBinding: Binding<ArticleDestination?> {
        Binding(
            get: { state.destination },
            set: { destination in
                if let destination { send(.present(destination)) } else { send(.dismiss) }
            }
        )
    }

    private var headingOrdinal: Int? {
        guard let piece = state.trackedPiece, pieces.indices.contains(piece) else { return nil }
        return ArticleBody.headingOrdinals(in: pieces)[...piece].compactMap { $0 }.last
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

private struct NoteEditor: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    let package: ImportPackage
    let block: Block
    @State private var state: NoteEditorState

    init(package: ImportPackage, block: Block, initialText: String) {
        self.package = package
        self.block = block
        _state = State(initialValue: .editing(initialText))
    }

    var body: some View {
        NavigationStack {
            Form { TextEditor(text: draftBinding).frame(minHeight: 180) }
                .navigationTitle("Note")
                .toolbar {
                    Button("Cancel") { send(.cancel) }.disabled(state.isSaving)
                    Button("Save") { send(.save) }
                        .disabled(state.isSaving || state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
        }
        .interactiveDismissDisabled(state.isSaving)
        .alert("Save failed", isPresented: .init(
            get: { state.failure != nil },
            set: { if !$0 { send(.dismissFailure) } }
        )) {
            Button("OK") { send(.dismissFailure) }
        } message: { Text(state.failure ?? "") }
    }

    private var draftBinding: Binding<String> {
        Binding(get: { state.draft }, set: { send(.changeDraft($0)) })
    }

    private func send(_ action: NoteEditorAction) {
        let wasSaving = state.isSaving
        state = reduce(state, action)
        switch action {
        case .save:
            guard case .saving = state, !wasSaving else { return }
            let text = state.draft
            Task {
                do {
                    try await library.save(note: text, materialID: package.material.id, blockID: block.id)
                    send(.saveSucceeded)
                } catch {
                    send(.saveFailed(error.localizedDescription))
                }
            }
        case .cancel, .saveSucceeded:
            dismiss()
        default:
            break
        }
    }
}

private enum NoteEditorState: Equatable {
    case editing(String)
    case saving(String)
    case failed(draft: String, message: String)
    case closed

    var draft: String {
        switch self {
        case let .editing(draft), let .saving(draft), let .failed(draft, _): draft
        case .closed: ""
        }
    }

    var isSaving: Bool {
        guard case .saving = self else { return false }
        return true
    }

    var failure: String? {
        guard case let .failed(_, message) = self else { return nil }
        return message
    }
}

private enum NoteEditorAction {
    case changeDraft(String)
    case save
    case saveSucceeded
    case saveFailed(String)
    case dismissFailure
    case cancel
}

private func reduce(_ state: NoteEditorState, _ action: NoteEditorAction) -> NoteEditorState {
    switch (state, action) {
    case let (.editing, .changeDraft(draft)), let (.failed, .changeDraft(draft)): .editing(draft)
    case let (.editing(draft), .save), let (.failed(draft, _), .save): .saving(draft)
    case (.saving, .saveSucceeded), (.editing, .cancel), (.failed, .cancel): .closed
    case let (.saving(draft), .saveFailed(message)): .failed(draft: draft, message: message)
    case let (.failed(draft, _), .dismissFailure): .editing(draft)
    default: state
    }
}
