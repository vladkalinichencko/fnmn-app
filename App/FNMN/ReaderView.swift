import SwiftUI

private enum ReaderDestination: String, Identifiable {
    case outline
    case note

    var id: String { rawValue }
}

private struct ReaderState {
    var index = 0
    var destination: ReaderDestination?
}

private enum ReaderAction {
    case restore(Int)
    case move(Int)
    case present(ReaderDestination)
    case dismiss
}

private func reduce(_ state: ReaderState, _ action: ReaderAction, blockCount: Int) -> ReaderState {
    var state = state
    switch action {
    case let .restore(index), let .move(index):
        if 0 ..< blockCount ~= index { state.index = index }
    case let .present(destination):
        state.destination = destination
    case .dismiss:
        state.destination = nil
    }
    return state
}

struct ReaderView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    let package: ImportPackage
    @State private var state = ReaderState()

    var body: some View {
        Group {
            if package.blocks.isEmpty {
                ContentUnavailableView("This material has no readable blocks", systemImage: "doc")
            } else {
                VStack {
                    blockView(package.blocks[state.index])
                    Divider()
                    HStack {
                        Button("Previous", systemImage: "chevron.left") { send(.move(state.index - 1)) }.disabled(state.index == 0)
                        Spacer()
                        Text("\(state.index + 1) of \(package.blocks.count)").foregroundStyle(.secondary)
                        Spacer()
                        Button("Next", systemImage: "chevron.right") { send(.move(state.index + 1)) }.disabled(state.index + 1 == package.blocks.count)
                    }
                    .padding()
                }
                .gesture(MagnifyGesture().onEnded {
                    value in if value.magnification < 0.8 {
                        send(.present(.outline))
                    }
                })
            }
        }
        .navigationTitle(package.material.title)
        .toolbar {
            Button("Sections", systemImage: "list.bullet.indent") { send(.present(.outline)) }
            Button(currentNote == nil ? "Add note" : "Edit note", systemImage: "note.text.badge.plus") { send(.present(.note)) }
            Link("Source", destination: package.material.sourceURL)
        }
        .sheet(item: destinationBinding) { destination in
            switch destination {
            case .outline:
                NavigationStack {
                    List(package.sections) { section in
                        Button {
                            open(blockID: section.firstBlockID)
                            send(.dismiss)
                        } label: {
                            Text(section.title).padding(.leading, CGFloat(max(0, section.level - 1)) * 12)
                        }
                    }
                    .navigationTitle("Sections")
                }
            case .note:
                if let block = currentBlock {
                    NoteEditor(package: package, block: block, initialText: currentNote?.text ?? "")
                }
            }
        }
        .task { restore() }
    }

    private var currentBlock: Block? {
        package.blocks.indices.contains(state.index) ? package.blocks[state.index] : nil
    }

    private var currentNote: Note? {
        guard let blockID = currentBlock?.id else { return nil }
        return library.snapshot.notes.first { $0.materialID == package.material.id && $0.blockID == blockID }
    }

    private func restore() {
        guard let position = library.snapshot.positions[package.material.id] else { return }
        guard let target = package.blocks.firstIndex(where: { $0.id == position.blockID }) else { return }
        send(.restore(target))
    }

    private func open(blockID: String) {
        guard let target = package.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        send(.move(target))
    }

    private var destinationBinding: Binding<ReaderDestination?> {
        Binding(get: { state.destination }, set: { destination in
            if let destination { send(.present(destination)) } else { send(.dismiss) }
        })
    }

    private func send(_ action: ReaderAction) {
        let previousIndex = state.index
        state = reduce(state, action, blockCount: package.blocks.count)
        guard case .move = action, state.index != previousIndex else { return }
        let position = ReadingPosition(blockID: package.blocks[state.index].id)
        Task { await library.save(position: position, materialID: package.material.id) }
    }

    private func blockView(_ block: Block) -> some View {
        BlockWebView(
            block: block,
            sourceURL: package.material.sourceURL,
            resumeSeconds: library.snapshot.positions[package.material.id]?.videoSeconds,
            scenePhase: scenePhase,
        ) { seconds in
            Task { await library.saveVideoTime(seconds, materialID: package.material.id, blockID: block.id) }
        }
        .id(block.id)
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
        state = reduce(state, action)
        switch action {
        case .save:
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
