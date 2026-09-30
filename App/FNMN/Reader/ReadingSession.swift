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

/// How far two fingers have pinched. Only the blocks the pinch moves read it, so a frame of the gesture redraws
/// those blocks and not the whole reader.
@MainActor @Observable
final class PinchScale {
    /// The scale of the fingers: 1 at rest, below 1 while they come together, above 1 while they spread.
    var value: CGFloat = 1
    /// Fingers have spread: the blocks the next fold out brings back are in the column, closed, until they let go.
    var spreading = false
    /// Fingers have let go and the blocks are finishing what the pinch began; a cancelled gesture must not begin again.
    @ObservationIgnored var settling = false

    /// The scale change that carries a block fully away or fully back.
    static let span: CGFloat = 0.35

    /// How far the blocks that leave have gone, 0 to 1.
    var leaving: CGFloat { min(max((1 - value) / Self.span, 0), 1) }
    /// How far the blocks that arrive have come, 0 to 1.
    var arriving: CGFloat { min(max((value - 1) / Self.span, 0), 1) }
}

/// One open document drawn from its coordinator: the column of blocks, the header and the pinch between sections.
/// Each block gets only values, so when the place moves one paragraph, SwiftUI redraws just the blocks
/// whose read state changed.
struct ReadingSession: View {
    @Environment(LibraryModel.self) private var library
    let reader: ReaderCoordinator
    @State private var pinch = PinchScale()
    /// Tells a cancelled pinch, which never ends, from one that was let go.
    @GestureState private var pinching = false

    var body: some View {
        let document = reader.document
        let visible = reader.visible
        let current = reader.current(in: visible)
        let leaving = readingFoldLeaving(reader.state.fold, blocks: document.blocks)
        let arriving = pinch.spreading ? readingFoldArriving(reader.state.fold, blocks: document.blocks) : []
        let marks = Dictionary(grouping: library.snapshot.annotations.filter { $0.materialID == reader.materialID }, by: \.piece)
        let progress = library.progress
        ScrollView {
            // The gap under a block belongs to the block, so it closes up with it.
            LazyVStack(alignment: .leading, spacing: 0) {
                if let lead = document.lead, case let .image(_, path) = document.blocks[lead] {
                    LeadImage(url: reader.baseURL.appending(path: path)).padding(.bottom, Tokens.gap)
                }
                MaterialHeader(title: reader.title, source: reader.source).padding(.bottom, 2 * Tokens.gap)
                ForEach(pinch.spreading ? reader.visibleWhileSpreading : visible, id: \.self) { index in
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
                    .padding(.bottom, Tokens.gap)
                    .modifier(PinchFold(role: leaving.contains(index) ? .leaves : arriving.contains(index) ? .arrives : .stays))
                    .id(index)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Tokens.gutter)
            .padding(.bottom, 80)
        }
        .scrollPosition(Bindable(reader).position, anchor: .top)
        // The place is read off the rows the person sees, never through the position that moves the column:
        // a position written back on each step made the column pull the next block to its top while scrolling up.
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.01) { shown in
            if let top = shown.min() { reader.send(.scrolled(top)) }
        }
        // The column is laid out unseen at the top and shows only once it stands where it opens, so the jump there is never seen.
        .animation(.easeOut(duration: 0.3)) { $0.opacity(reader.state.hidesColumn ? 0 : 1) }
        // After the first layout, when the lazy column knows its rows and can go to one far down.
        .task {
            await Task.yield()
            reader.send(.opened)
        }
        .simultaneousGesture(
            MagnifyGesture()
                .updating($pinching) { _, state, _ in state = true }
                .onChanged { fingers in
                    pinch.value = fingers.magnification
                    if fingers.magnification > 1.03 { pinch.spreading = true }
                }
                .onEnded { settle($0.magnification) }
        )
        .onChange(of: pinching) { _, now in
            if !now, !pinch.settling { settle(1) }
        }
        .environment(pinch)
        .environment(reader)
        .toolbar { selectionToolbar }
    }

    /// Fingers let go: the blocks finish closing or opening, or go back if the pinch did not reach a fold, and only
    /// then does the fold change, so nothing jumps.
    private func settle(_ scale: CGFloat) {
        let folds = readingFoldPinched(reader.state.fold, scale: Double(scale), blocks: reader.document.blocks) != reader.state.fold
        pinch.settling = true
        let end = !folds ? 1 : scale < 1 ? 1 - PinchScale.span : 1 + PinchScale.span
        withAnimation(.smooth(duration: 0.3)) {
            pinch.value = end
        } completion: {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                if folds { reader.send(.pinched(scale)) }
                pinch.value = 1
                pinch.spreading = false
                pinch.settling = false
            }
        }
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
