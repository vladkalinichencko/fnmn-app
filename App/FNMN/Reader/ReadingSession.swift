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

/// What a plate can do with itself or with text selected in it. The same actions back the
/// plate's context menu, the edit menu of selected text and the toolbar of ticked plates.
struct ParagraphActions {
    let materialID: String
    let annotations: [Annotation]
    let perform: (AnnotationCommand, AnnotationTarget) -> Void
    let ask: (String) -> Void
    let copyPrompt: (String) -> Void

    func target(_ piece: Int, text: String, quote: String? = nil) -> AnnotationTarget {
        let span = quote.flatMap { quote -> TextSpan? in
            let found = (text as NSString).range(of: quote)
            return found.location == NSNotFound ? nil : TextSpan(start: found.location, length: found.length)
        }
        return AnnotationTarget(materialID: materialID, piece: piece, text: text, span: span)
    }

    func commands(_ target: AnnotationTarget) -> [AnnotationCommand] {
        annotationCommands(annotations, at: target)
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

/// One open document: the column of blocks, the place at the top, the plate mode and the pinch between sections.
struct ReadingSession: View {
    @Environment(LibraryModel.self) private var library
    let document: ReaderDocument
    let materialID: String
    let header: MaterialHeader
    let baseURL: URL
    let piece: Int?
    var onVisiblePiece: (Int) -> Void = { _ in }

    @State private var fold = ReadingFold.open
    @State private var mode = PlateMode.reading
    @State private var place: Int?
    @State private var scrollID: Int?
    @State private var holdingPlace = false
    @GestureState private var pinch: CGFloat = 1

    private var blocks: [DocumentBlock] { document.blocks }
    private var sections: [Int: HeadingSection] { document.sections }

    var body: some View {
        let visible = visiblePieceIndexes(in: blocks, fold: fold).filter { $0 != document.repeatedTitle && $0 != document.lead }
        let current = readingPlaceTarget(place: place ?? piece, visible: visible)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.gap) {
                if let lead = document.lead, case let .image(_, path) = blocks[lead] {
                    LeadImage(url: baseURL.appending(path: path))
                }
                header.padding(.bottom, Tokens.gap)
                ForEach(visible, id: \.self) { index in
                    BlockView(
                        block: blocks[index],
                        index: index,
                        baseURL: baseURL,
                        current: current,
                        mode: mode,
                        pinch: pinch,
                        folded: fold == .open ? nil : sections[index]?.size ?? 0,
                        sectionRead: (sections[index]?.end).map { end in (place ?? piece).map { end <= $0 } ?? false } ?? false,
                        actions: actions,
                        send: send,
                        openSection: openSection
                    )
                    .id(index)
                    .transition(.foldIntoHeading)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Tokens.gutter)
            .padding(.bottom, 80)
        }
        .swipeActionsContainer()
        .scrollPosition(id: $scrollID, anchor: .top)
        .onChange(of: piece, initial: true) { _, piece in
            guard let piece else { return }
            place = piece
            guard scrollID != piece else { return }
            holdingPlace = true
            scrollID = piece
        }
        .onChange(of: scrollID) { _, index in
            guard let index, blocks.indices.contains(index) else { return }
            // Scrolling the outline moves between headings, not through the text: the place stays where reading stopped.
            if holdingPlace || fold != .open {
                holdingPlace = false
                return
            }
            place = index
            onVisiblePiece(index)
        }
        .simultaneousGesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in pinched(value.magnification, current: current) }
        )
        .toolbar { selectionToolbar }
    }

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        if case let .selectingParagraphs(picked) = mode {
            ToolbarItemGroup(placement: .bottomBar) {
                let texts = picked.sorted().compactMap(text(of:))
                Button("Highlight", systemImage: "highlighter") {
                    for index in picked.sorted() {
                        guard let text = text(of: index) else { continue }
                        actions.perform(.mark(.highlight), actions.target(index, text: text))
                    }
                    send(.done)
                }
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = texts.joined(separator: "\n\n")
                    send(.done)
                }
                Button("Ask ChatGPT", systemImage: "bubble.left.and.text.bubble.right") {
                    actions.ask(texts.joined(separator: "\n\n"))
                    send(.done)
                }
                Spacer()
                Button("Done") { send(.done) }
            }
        } else if mode != .reading {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { send(.done) }
            }
        }
    }

    private var actions: ParagraphActions {
        ParagraphActions(
            materialID: materialID,
            annotations: library.snapshot.annotations.filter { $0.materialID == materialID },
            perform: { command, target in
                let change: LibraryChange = switch command {
                case let .mark(mark): .mark(mark, target)
                case let .unmark(mark): .unmark(mark, target)
                }
                Task { await library.apply(change) }
            },
            ask: { ChatGPTHandoff.copyAndOpen(title: header.title, passage: $0) },
            copyPrompt: { _ = ChatGPTHandoff.remember(title: header.title, passage: $0) }
        )
    }

    private func send(_ action: PlateAction) {
        withAnimation(.snappy) { mode = plateReduce(mode, action) }
    }

    private func text(of index: Int) -> String? {
        guard case let .text(markdown) = blocks[index] else { return nil }
        return MarkedMarkdown.plainText(markdown, baseURL: baseURL)
    }

    /// Pinching in folds the document one heading level at a time; spreading unfolds it.
    private func pinched(_ scale: CGFloat, current: Int?) {
        let next: ReadingFold
        if scale < 0.9 {
            next = readingFoldPinchIn(fold, blocks: blocks)
        } else if scale > 1.1 {
            next = readingFoldPinchOut(fold, blocks: blocks)
        } else {
            return
        }
        guard next != fold else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { fold = next }
        let shown = visiblePieceIndexes(in: blocks, fold: next)
        guard let target = readingPlaceTarget(place: place ?? piece, visible: shown), scrollID != target else { return }
        holdingPlace = true
        scrollID = target
    }

    /// Tapping a heading in the folded document opens the whole text at that section.
    private func openSection(_ index: Int) {
        guard fold != .open else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { fold = .open }
        holdingPlace = true
        scrollID = index
    }
}
