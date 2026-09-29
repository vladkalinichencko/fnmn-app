import FNMNCore
import SwiftUI

/// What the reader is doing with its plates: just reading, selecting text in one plate,
/// ticking several plates, or writing a margin note.
enum PlateMode: Equatable {
    case reading
    case selectingText(Int)
    case selectingParagraphs(Set<Int>)
    case noting(Int)
}

enum PlateAction {
    case selectText(Int)
    case selectParagraphs(from: Int)
    case toggle(Int)
    case note(Int)
    case done
}

func plateReduce(_ mode: PlateMode, _ action: PlateAction) -> PlateMode {
    switch (mode, action) {
    case let (_, .selectText(index)): .selectingText(index)
    case let (_, .selectParagraphs(index)): .selectingParagraphs([index])
    case let (.selectingParagraphs(picked), .toggle(index)): .selectingParagraphs(picked.symmetricDifference([index]))
    case (_, .toggle): mode
    case let (_, .note(index)): .noting(index)
    case (_, .done): .reading
    }
}

extension AnnotationCommand {
    var title: String {
        switch self {
        case .mark(.highlight): "Highlight"
        case .unmark(.highlight): "Remove Highlight"
        case .mark(.strikethrough): "Strikethrough"
        case .unmark(.strikethrough): "Remove Strikethrough"
        }
    }

    var systemImage: String {
        switch self {
        case .mark(.highlight), .unmark(.highlight): "highlighter"
        case .mark(.strikethrough), .unmark(.strikethrough): "strikethrough"
        }
    }
}

/// How far two fingers have pinched. Only the blocks' fold effect reads it, so a frame of the gesture
/// redraws that effect and not the whole reader.
@MainActor @Observable
final class PinchScale {
    var value: CGFloat = 1
}

/// One open document drawn from its coordinator: the column of blocks, the header and the pinch between sections.
/// Each block gets only values, so when the place moves one paragraph, SwiftUI redraws just the blocks
/// whose read state changed.
struct ReadingSession: View {
    @Environment(LibraryModel.self) private var library
    let reader: ReaderCoordinator
    @State private var pinch = PinchScale()
    /// Resets the pinch when the gesture ends or is cancelled.
    @GestureState private var pinching = false

    var body: some View {
        let document = reader.document
        let visible = reader.visible
        let current = reader.current(in: visible)
        let marks = Dictionary(grouping: library.snapshot.annotations.filter { $0.materialID == reader.materialID }, by: \.piece)
        let progress = library.progress
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.gap) {
                if let lead = document.lead, case let .image(_, path) = document.blocks[lead] {
                    LeadImage(url: reader.baseURL.appending(path: path))
                }
                MaterialHeader(title: reader.title, source: reader.source).padding(.bottom, Tokens.gap)
                ForEach(visible, id: \.self) { index in
                    let section = document.sections[index]
                    BlockView(
                        block: document.blocks[index],
                        index: index,
                        baseURL: reader.baseURL,
                        mode: reader.state.mode,
                        read: progress.isPieceRead(index, of: reader.materialID, current: current),
                        markedReadThrough: progress.readThrough[reader.materialID] == index,
                        annotations: marks[index] ?? [],
                        folded: reader.state.fold == .open ? nil : section?.size ?? 0,
                        sectionRead: section.map { section in reader.state.place.map { section.end <= $0 } ?? false } ?? false
                    )
                    .equatable()
                    .id(index)
                    .transition(.foldIntoHeading)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Tokens.gutter)
            .padding(.bottom, 80)
        }
        .swipeActionsContainer()
        .scrollPosition(id: reader.scrollPosition, anchor: .top)
        .simultaneousGesture(
            MagnifyGesture()
                .updating($pinching) { _, state, _ in state = true }
                .onChanged { pinch.value = $0.magnification }
                .onEnded { reader.send(.pinched($0.magnification)) }
        )
        .onChange(of: pinching) { _, now in
            if !now { pinch.value = 1 }
        }
        .environment(pinch)
        .environment(reader)
        .toolbar { selectionToolbar }
    }

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        if case let .selectingParagraphs(picked) = reader.state.mode {
            ToolbarItemGroup(placement: .bottomBar) {
                let texts = picked.sorted().compactMap(text(of:))
                Button("Highlight", systemImage: "highlighter") {
                    for index in picked.sorted() {
                        guard let text = text(of: index) else { continue }
                        reader.send(.mark(.mark(.highlight), reader.target(index, text: text)))
                    }
                    reader.send(.plate(.done))
                }
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = texts.joined(separator: "\n\n")
                    reader.send(.plate(.done))
                }
                Button("Ask ChatGPT", systemImage: "bubble.left.and.text.bubble.right") {
                    reader.send(.ask(texts.joined(separator: "\n\n")))
                    reader.send(.plate(.done))
                }
                Spacer()
                Button("Done") { reader.send(.plate(.done)) }
            }
        } else if reader.state.mode != .reading {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { reader.send(.plate(.done)) }
            }
        }
    }

    private func text(of index: Int) -> String? {
        guard case let .text(markdown) = reader.document.blocks[index] else { return nil }
        return MarkedMarkdown.plainText(markdown, baseURL: reader.baseURL)
    }
}
