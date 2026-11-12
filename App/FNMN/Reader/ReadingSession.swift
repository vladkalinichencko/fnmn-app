import FNMNCore
import SwiftUI
import Textual

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

struct ReadingSession: View {
    @Environment(LibraryModel.self) private var library
    let reader: ReaderCoordinator
    @State private var width: CGFloat = 0
    @State private var columnWidth: CGFloat = 0
    @AppStorage(ReaderAppearance.lineKey) private var showsLine = false
    @AppStorage(ReaderAppearance.columnKey) private var column = ReaderColumn.regular
    @Namespace private var mediaZoom

    var body: some View {
        let document = reader.document
        let visible = reader.visible
        let line = reader.state.showsLine ? reader.state.line : nil
        let current = reader.current(in: visible)
        let marks = Dictionary(grouping: library.snapshot.annotations.filter { $0.materialID == reader.materialID }, by: \.piece)
        let progress = library.progress
        let marked: Int? = if let line {
            line.fraction == 0 ? visible.last { $0 < line.piece } : line.fraction >= 1 ? line.piece : nil
        } else {
            progress.readThrough[reader.materialID]
        }
        let paging = reader.state.shownPlate != nil
        let found = reader.state.find?.matches ?? []
        let findsByBlock = Dictionary(grouping: found, by: \.piece)
        let activeFind = reader.state.find?.current.map { found[$0] }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let lead = document.lead, case let .image(_, path) = document.blocks[lead] {
                        let cover = reader.baseURL.appending(path: path)
                        LeadImage(url: cover)
                            .opensMedia(cover)
                            .padding(.bottom, Tokens.gap)
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
                            fold: fold(of: index, in: document),
                            finds: findsByBlock[index]?.map(\.span) ?? [],
                            activeFind: activeFind?.piece == index ? activeFind?.span : nil,
                            spot: reader.spotSpan(of: index)
                        )
                        .equatable()
                        .padding(.bottom, Tokens.gap)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.column)) } action: { reader.rowChanged(index, $0) }
                        .modifier(Reveal(isNew: reader.revealed.contains(index)))
                        .id(index)
                    }
                }
                .scrollTargetLayout()
                .textual.onTextLinesChange { reader.textLinesChanged($0) }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, 80)
                .frame(maxWidth: width > 0 ? column.width(in: width) : .infinity)
                .frame(maxWidth: .infinity)
                .overlay {
                    if line != nil { ReadingLineView(reader: reader) }
                }
                .coordinateSpace(.named(Self.column))
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.01) { shown in
                reader.shownChanged(shown)
                if let top = shown.min() { reader.send(.scrolled(top)) }
            }
            .onChange(of: showsLine) { reader.send(.showLine(showsLine)) }
            .animation(.easeOut(duration: 0.3)) { $0.opacity(reader.state.hidesColumn ? 0 : 1) }
            .animation(.smooth(duration: 0.35)) { $0.blur(radius: paging ? 16 : 0) }
            .allowsHitTesting(!paging)
            .accessibilityHidden(paging)
            .environment(\.mediaZoom, paging ? nil : mediaZoom)
            .task(id: ObjectIdentifier(reader)) {
                reader.scroll = { proxy.scrollTo($0, anchor: .top) }
                await Task.yield()
                reader.send(.opened)
            }
        }
        .overlay {
            ZStack {
                if let plate = reader.state.shownPlate {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    PlatePager(reader: reader, plate: plate, width: width > 0 ? column.width(in: width) : nil)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .animation(.smooth(duration: 0.35), value: paging)
        }
        .environment(reader)
        .environment(\.mediaZoom, mediaZoom)
        .environment(\.plateTextWidth, columnWidth > 0 ? columnWidth - 2 * Tokens.tilePadding : nil)
        .environment(\.openURL, OpenURLAction { url in
            guard url.isFileURL, ImageFiles.headerSize(of: url) != nil else { return .systemAction }
            reader.send(.openMedia(url))
            return .handled
        })
        .fullScreenCover(isPresented: Binding(get: { reader.state.media != nil }, set: { if !$0 { reader.send(.closeMedia) } })) {
            if let media = reader.state.media {
                MediaViewer(url: media)
                    .navigationTransition(.zoom(sourceID: media, in: mediaZoom))
            }
        }
        .overlay(alignment: .bottom) {
            if let spot = reader.state.spot {
                SpotControls(reader: reader, running: spot.running)
                    .padding(.bottom, 12)
            }
        }
        .toolbar {
            if reader.state.mode != .reading {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { reader.send(.plate(.done)) }
                }
            }
        }
    }

    nonisolated static let column = "column"

    private func fold(of index: Int, in document: ReaderDocument) -> HeadingFold {
        guard document.holdsBlocks(index), let section = document.sections[index] else { return .none }
        return reader.state.folded.contains(index) ? .closed(hidden: section.size) : .open
    }
}

private struct Reveal: ViewModifier {
    @State private var shown: Bool

    init(isNew: Bool) {
        _shown = State(initialValue: !isNew)
    }

    func body(content: Content) -> some View {
        content
            .visualEffect { [shown] content, _ in
                content
                    .offset(y: shown ? 0 : -10)
                    .opacity(shown ? 1 : 0)
                    .blur(radius: shown ? 0 : 5)
            }
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(duration: 0.32, bounce: 0.22)) { shown = true }
            }
    }
}

struct SpotControls: View {
    let reader: ReaderCoordinator
    let running: Bool

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button(running ? "Pause" : "Play", systemImage: running ? "pause.fill" : "play.fill") {
                    reader.send(.spotPaused(running))
                }
                .buttonStyle(.glass)
                Button("Done", systemImage: "xmark") {
                    reader.send(.spot(false))
                }
                .buttonStyle(.glass)
            }
        }
    }
}
