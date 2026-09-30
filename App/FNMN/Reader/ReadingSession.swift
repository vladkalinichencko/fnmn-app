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
    /// Where each block lies in the column. Nothing is drawn from it directly, so it is not observed; a fold
    /// reads it when fingers move.
    @ObservationIgnored var frames: [Int: CGRect] = [:]

    /// How far a block rises to reach the lower edge of the block it folds into; to the top of the column
    /// when nothing above it stays.
    func rise(of index: Int, into parent: Int?) -> CGFloat {
        guard let frame = frames[index] else { return 0 }
        let floor = parent.flatMap { frames[$0]?.maxY } ?? 0
        return max(frame.minY - floor, 0)
    }
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
    /// Read in `onGeometryChange`'s transform, which runs off the main actor.
    private nonisolated static let column = "column"

    var body: some View {
        let document = reader.document
        let visible = reader.visible
        let current = reader.current(in: visible)
        let marks = Dictionary(grouping: library.snapshot.annotations.filter { $0.materialID == reader.materialID }, by: \.piece)
        let progress = library.progress
        let foldParents = readingFoldParents(reader.state.fold, blocks: document.blocks)
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
                        sectionRead: section.map { progress.isPieceRead($0.end - 1, of: reader.materialID, current: reader.state.place) } ?? false
                    )
                    .equatable()
                    .modifier(PinchFold(index: index, folding: foldParents.keys.contains(index), parent: foldParents[index] ?? nil))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.column)) } action: { pinch.frames[index] = $0 }
                    .id(index)
                    .transition(.fold(index, into: foldParents[index] ?? nil))
                }
            }
            .coordinateSpace(.named(Self.column))
            .scrollTargetLayout()
            .padding(.horizontal, Tokens.gutter)
            .padding(.bottom, 80)
        }
        .swipeActionsContainer()
        .scrollPosition(Bindable(reader).position, anchor: .top)
        // The place is read off the rows the person sees, never through the position that moves the column:
        // a position written back on each step made the column pull the next block to its top while scrolling up.
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.01) { shown in
            if let top = shown.min() { reader.send(.scrolled(top)) }
        }
        // The column is laid out unseen at the top and shows only once it stands where it opens, so the jump there is never seen.
        .animation(.easeOut(duration: 0.3)) { $0.opacity(reader.state.opening == nil ? 1 : 0) }
        // After the first layout, when the lazy column knows its rows and can go to one far down.
        .task {
            await Task.yield()
            reader.send(.opened)
        }
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
