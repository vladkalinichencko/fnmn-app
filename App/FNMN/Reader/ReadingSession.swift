import FNMNCore
import SwiftUI
import Textual

/// What the reader is doing with its plates: just reading, or writing a margin note.
enum PlateMode: Equatable {
    case reading
    case noting(Int)
}

enum PlateAction {
    case note(Int)
    case done
}

func plateReduce(_ mode: PlateMode, _ action: PlateAction) -> PlateMode {
    switch action {
    case let .note(index): .noting(index)
    case .done: .reading
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

/// One open document drawn from its coordinator: the column of blocks, the header and the headings that fold their sections.
/// Each block gets only values, so when the place moves one paragraph, SwiftUI redraws just the blocks
/// whose read state changed.
struct ReadingSession: View {
    @Environment(LibraryModel.self) private var library
    let reader: ReaderCoordinator
    @State private var width: CGFloat = 0
    @AppStorage(ReaderAppearance.lineKey) private var showsLine = false

    var body: some View {
        let document = reader.document
        let visible = reader.visible
        let line = reader.state.showsLine ? reader.state.line : nil
        let current = reader.current(in: visible)
        let marks = Dictionary(grouping: library.snapshot.annotations.filter { $0.materialID == reader.materialID }, by: \.piece)
        let progress = library.progress
        // The plate whose "read to here" holds: with the line, the one right above it when it stands at a block's top.
        let marked: Int? = if let line {
            line.fraction == 0 ? visible.last { $0 < line.piece } : nil
        } else {
            progress.readThrough[reader.materialID]
        }
        ScrollView {
            // The gap under a block belongs to the block, so it closes up with it.
            LazyVStack(alignment: .leading, spacing: 0) {
                if let lead = document.lead, case let .image(_, path) = document.blocks[lead] {
                    LeadImage(url: reader.baseURL.appending(path: path)).padding(.bottom, Tokens.gap)
                }
                MaterialHeader(title: reader.title, source: reader.source)
                    .padding(.bottom, 2 * Tokens.gap)
                ForEach(visible, id: \.self) { index in
                    BlockView(
                        block: document.blocks[index],
                        index: index,
                        baseURL: reader.baseURL,
                        mode: reader.state.mode,
                        readShare: line.map { progress.readShare(of: index, in: reader.materialID, line: $0) }
                            ?? (progress.isPieceRead(index, of: reader.materialID, current: current) ? 1 : 0),
                        markedReadThrough: marked == index,
                        annotations: marks[index] ?? [],
                        fold: fold(of: index, in: document)
                    )
                    .equatable()
                    .padding(.bottom, Tokens.gap)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.column)) } action: { reader.rowChanged(index, $0) }
                    .id(index)
                }
            }
            // On the stack itself: a modifier between them would make its own layout the one whose rows are watched.
            .scrollTargetLayout()
            .textual.onTextLinesChange { reader.textLinesChanged($0) }
            .padding(.horizontal, Tokens.gutter)
            .padding(.bottom, 80)
            // A wide screen reads in a narrower column in the middle; the scroll view itself keeps the whole width.
            .frame(maxWidth: width > 0 ? Tokens.readingWidth(in: width) : .infinity)
            .frame(maxWidth: .infinity)
            // The line runs across the whole screen, over the gutters; the column starts at the same height.
            .overlay {
                if line != nil { ReadingLineView(reader: reader) }
            }
            .coordinateSpace(.named(Self.column))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }        .scrollPosition(Bindable(reader).position, anchor: .top)
        // The place is read off the rows the person sees, never through the position that moves the column:
        // a position written back on each step made the column pull the next block to its top while scrolling up.
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.01) { shown in
            if let top = shown.min() { reader.send(.scrolled(top)) }
        }
        .onChange(of: showsLine) { reader.send(.showLine(showsLine)) }
        // The column is laid out unseen at the top and shows only once it stands where it opens, so the jump there is never seen.
        .animation(.easeOut(duration: 0.3)) { $0.opacity(reader.state.hidesColumn ? 0 : 1) }
        // After the first layout, when the lazy column knows its rows and can go to one far down.
        .task {
            await Task.yield()
            reader.send(.opened)
        }
        .environment(reader)
        .toolbar {
            if reader.state.mode != .reading {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { reader.send(.plate(.done)) }
                }
            }
        }
    }

    /// The reader's own coordinate space, shared by the rows' frames and the reading line. Geometry closures run off
    /// the main actor, so it belongs to none.
    nonisolated static let column = "column"

    private func fold(of index: Int, in document: ReaderDocument) -> HeadingFold {
        guard document.holdsBlocks(index), let section = document.sections[index] else { return .none }
        return reader.state.folded.contains(index) ? .closed(hidden: section.size) : .open
    }
}
