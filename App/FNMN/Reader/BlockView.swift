import AVKit
import FNMNCore
import SwiftUI
import Textual

/// The one place that decides how each kind of block is drawn.
struct BlockView: View {
    let block: DocumentBlock
    let index: Int
    let baseURL: URL
    let current: Int?
    let mode: PlateMode
    let pinch: CGFloat
    /// The number of blocks under this heading when the document is folded; nil while it is open.
    let folded: Int?
    /// A folded heading whose whole section lies before the reading place.
    let sectionRead: Bool
    let actions: ParagraphActions
    let send: (PlateAction) -> Void
    let openSection: (Int) -> Void

    var body: some View {
        switch block {
        case let .heading(level, title):
            HeadingView(level: level, title: title, folded: folded, read: sectionRead)
                .onTapGesture { openSection(index) }
        case let .text(markdown):
            PlateView(markdown: markdown, index: index, baseURL: baseURL, current: current, mode: mode, actions: actions, send: send)
                .modifier(PinchFold(pinch: pinch))
        case let .image(alt, path):
            StandaloneImage(url: resolve(path), alt: alt)
                .modifier(PinchFold(pinch: pinch))
        case let .video(path):
            ArticleVideo(url: resolve(path))
                .modifier(PinchFold(pinch: pinch))
        case let .interactive(url, selector):
            LiveCropView(url: url, selector: selector)
                .modifier(PinchFold(pinch: pinch))
        }
    }

    private func resolve(_ path: String) -> URL {
        if let url = URL(string: path), url.scheme != nil { return url }
        return baseURL.appending(path: path)
    }
}

/// While fingers pinch in, the blocks begin to fold up into their heading, as far as the fingers have gone.
private struct PinchFold: ViewModifier {
    let pinch: CGFloat

    func body(content: Content) -> some View {
        content.modifier(FoldIntoHeading(amount: min(max(1 - pinch, 0), 0.6) / 0.6 * 0.5))
    }
}

/// A block folding up toward the heading above it: it tips back about its top edge and flattens there.
/// At 1 it is folded away; the same effect carries the fold's transition and the pinch that leads to it.
struct FoldIntoHeading: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(-35 * amount), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.25)
            .scaleEffect(x: 1 - 0.06 * amount, y: 1 - 0.5 * amount, anchor: .top)
            .opacity(1 - amount)
    }
}

extension AnyTransition {
    static var foldIntoHeading: AnyTransition {
        AnyTransition.modifier(active: FoldIntoHeading(amount: 1), identity: FoldIntoHeading(amount: 0))
    }
}

/// A heading on the page. Open and folded it is the same view, so it slides to its place in the outline
/// instead of fading out and in; folded, it sits closer, shows how many blocks it holds and grays once read.
struct HeadingView: View {
    let level: Int
    let title: String
    var folded: Int?
    var read = false
    @AppStorage(ReaderAppearance.fontKey) private var readerFont = ReaderFont.system

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            InlineText(markdown: title, syntaxExtensions: [.math])
                .font(font)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let folded, folded > 0 {
                Text(folded, format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(read && folded != nil ? .secondary : .primary)
        .padding(.top, folded == nil ? (level <= 2 ? Tokens.gap : 4) : 4)
        .padding(.bottom, folded == nil ? 0 : 4)
        .contentShape(.rect)
    }

    private var font: Font {
        let style: Font.TextStyle = switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        default: .headline
        }
        return .system(style, design: readerFont.design).bold()
    }
}

/// The cover an article opens with, full width above its title.
struct LeadImage: View {
    let url: URL

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
        .clipShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
    }
}

/// A paragraph, list, quote, table or code block on its own rounded plate.
/// Dragging it left uncovers its margin note, which lies under the plate all along; the system's leading swipe marks "read to here".
struct PlateView: View {
    @Environment(LibraryModel.self) private var library
    let markdown: String
    let index: Int
    let baseURL: URL
    let current: Int?
    let mode: PlateMode
    let actions: ParagraphActions
    let send: (PlateAction) -> Void
    @State private var drag: CGFloat = 0
    @State private var width: CGFloat = 0

    private var noting: Bool { mode == .noting(index) }
    /// How far the plate moves aside for its note: a little over half its width.
    private var noteWidth: CGFloat { width * 0.58 }
    private var offset: CGFloat { (noting ? -noteWidth : 0) + drag }

    var body: some View {
        plate
            .frame(maxWidth: .infinity)
            .background(alignment: .trailing) {
                MarginNote(saved: paragraphNote, active: noting, save: saveNote)
                    .frame(width: noteWidth - Tokens.gap)
                    // Only the strip the plate has moved off shows, so the note seems to have been under it all along.
                    .mask(alignment: .trailing) { Rectangle().frame(width: max(-offset - Tokens.gap, 0)) }
                    .allowsHitTesting(noting)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .animation(.spring(duration: 0.35, bounce: 0.2), value: noting)
    }

    private func dragged(_ translation: CGFloat) {
        guard mode == .reading || noting else { return }
        drag = noting ? max(translation, 0) : max(min(translation, 0), -noteWidth - 20)
    }

    private func released(_ translation: CGFloat, _ velocity: CGFloat) {
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { drag = 0 }
        if noting {
            if translation > 60 || velocity > 500 { send(.done) }
        } else if translation < -60 || velocity < -500 {
            send(.note(index))
        }
    }

    private var plate: some View {
        StructuredText(markdown, parser: MarkedMarkdown(baseURL: baseURL, marks: marks))
            // StructuredText parses again only when the Markdown changes; new marks need a new parse.
            .id(marks)
            .textual.overflowMode(.wrap)
            .plateMarkdownStyles()
            .modifier(TextSelection(isOn: mode == .selectingText(index)))
            .environment(\.textualSelectionMenu, mode == .selectingText(index) ? selectionMenu : nil)
            .padding(Tokens.tilePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .plate(cornerRadius: Tokens.plateRadius)
            .overlay(alignment: .topTrailing) {
                if let tick { tick } else { noteMark }
            }
            .opacity(isRead && mode == .reading ? 0.55 : 1)
            .contentShape(.rect(cornerRadius: Tokens.plateRadius, style: .continuous))
            .modifier(TickOnTap(isOn: isTicking) { send(.toggle(index)) })
            .modifier(TickOnTap(isOn: noting) { send(.done) })
            .contextMenu { if mode == .reading { menu } }
            // Inside the system's swipe, which places the row itself and would undo an offset put around it.
            .offset(x: offset)
            // Leftward belongs to the note; rightward to the system's swipe, or to closing an open note.
            .gesture(HorizontalPan(starts: { noting ? $0 > 0 : $0 < 0 }, changed: dragged, ended: released))
            .swipeActions(edge: .leading) {
                if mode == .reading {
                    let marked = library.snapshot.readThrough[actions.materialID] == index
                    Button(marked ? "Unmark" : "Read to Here", systemImage: marked ? "arrow.uturn.backward" : "checkmark") {
                        Task { await library.apply(.readThrough(piece: marked ? nil : index, itemID: actions.materialID)) }
                    }
                    .tint(.accentColor)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: marks)
            .sensoryFeedback(.selection, trigger: library.snapshot.readThrough[actions.materialID] == index)
    }

    @ViewBuilder
    private var menu: some View {
        let text = plainText
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
        let target = actions.target(index, text: text)
        ForEach(actions.commands(target), id: \.title) { command in
            Button(command.title, systemImage: command.systemImage) { actions.perform(command, target) }
        }
        Button("Select Text", systemImage: "character.cursor.ibeam") { send(.selectText(index)) }
        Button("Select Paragraphs", systemImage: "checklist") { send(.selectParagraphs(from: index)) }
        Button("Add Note", systemImage: "note.text") { send(.note(index)) }
        Button("Ask ChatGPT", systemImage: "bubble.left.and.text.bubble.right") { actions.ask(text) }
        Button("Copy as Prompt", systemImage: "text.quote") { actions.copyPrompt(text) }
        let pictures = ArticleBody.imagePaths(in: markdown).compactMap { UIImage(contentsOfFile: baseURL.appending(path: $0).path) }
        ForEach(Array(pictures.enumerated()), id: \.offset) { number, picture in
            Button(pictures.count == 1 ? "Save Picture to Photos" : "Save Picture \(number + 1) to Photos", systemImage: "square.and.arrow.down") {
                UIImageWriteToSavedPhotosAlbum(picture, nil, nil, nil)
            }
        }
    }

    private var selectionMenu: @MainActor (String) -> [UIMenuElement] {
        let text = plainText
        let actions = actions
        let index = index
        return { selected in
            let target = actions.target(index, text: text, quote: selected)
            let marks = actions.commands(target).map { command in
                UIAction(title: command.title, image: UIImage(systemName: command.systemImage)) { _ in actions.perform(command, target) }
            }
            let ask = UIAction(title: "Ask ChatGPT", image: UIImage(systemName: "bubble.left.and.text.bubble.right")) { _ in actions.ask(selected) }
            return marks + [ask]
        }
    }

    private var tick: AnyView? {
        guard case let .selectingParagraphs(picked) = mode else { return nil }
        return AnyView(
            Image(systemName: picked.contains(index) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(picked.contains(index) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .padding(10)
        )
    }

    /// A small tab on the right edge of a plate that has a note; the note itself shows when the plate is pulled aside.
    @ViewBuilder
    private var noteMark: some View {
        if !paragraphNote.isEmpty, offset == 0 {
            Capsule()
                .fill(.tint)
                .frame(width: 4, height: 22)
                .padding(.top, Tokens.tilePadding + 2)
                .offset(x: 2)
        }
    }

    private var isTicking: Bool {
        if case .selectingParagraphs = mode { true } else { false }
    }

    private var isRead: Bool {
        library.snapshot.isPieceRead(index, of: actions.materialID, current: current)
    }

    private var marks: [ParagraphQuoteMark] {
        actions.annotations.compactMap { annotation in
            guard annotation.piece == index, let mark = annotation.mark, !annotation.quote.isEmpty else { return nil }
            return ParagraphQuoteMark(quote: annotation.quote, mark: mark)
        }
    }

    /// The note on the whole paragraph. It is stored with the paragraph's text as its quote, so the shelf can show both.
    private var paragraphNote: String {
        let text = plainText
        return actions.annotations.first { $0.piece == index && !$0.note.isEmpty && ($0.quote.isEmpty || $0.quote == text) }?.note ?? ""
    }

    private var plainText: String {
        MarkedMarkdown.plainText(markdown, baseURL: baseURL)
    }

    private func saveNote(_ text: String) {
        let paragraph = plainText
        Task { await library.apply(.note(text, actions.target(index, text: paragraph, quote: paragraph))) }
    }
}

/// A note in the margin beside its paragraph: plain text on the page, no frame, saved when it closes.
/// It is as tall as its paragraph; a longer note scrolls, fading out at the edge it continues past.
private struct MarginNote: View {
    let saved: String
    let active: Bool
    let save: (String) -> Void
    @State private var draft = ""
    @State private var overflow = Overflow()
    @FocusState private var focused: Bool
    @AppStorage(ReaderAppearance.fontKey) private var readerFont = ReaderFont.system

    var body: some View {
        ScrollView {
            TextField("Note", text: $draft, axis: .vertical)
                .font(.system(.callout, design: readerFont.design))
                .focused($focused)
                .padding(.vertical, Tokens.tilePadding)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: Overflow.self) { geometry in
            Overflow(
                above: geometry.contentOffset.y > 1,
                below: geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
            )
        } action: { _, new in
            overflow = new
        }
        .mask(fade)
        .onAppear { draft = saved }
        .onChange(of: saved) { draft = saved }
        .onChange(of: active) {
            if active {
                focused = saved.isEmpty
            } else {
                focused = false
                if draft != saved { save(draft) }
            }
        }
    }

    private var fade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: overflow.above ? 20 : 0)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: overflow.below ? 20 : 0)
        }
    }

    private struct Overflow: Equatable {
        var above = false
        var below = false
    }
}

private struct TextSelection: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.textual.textSelection(.enabled)
        } else {
            content.textual.textSelection(.disabled)
        }
    }
}

private struct TickOnTap: ViewModifier {
    let isOn: Bool
    let toggle: () -> Void

    func body(content: Content) -> some View {
        if isOn {
            content.onTapGesture(perform: toggle)
        } else {
            content
        }
    }
}

/// A picture that stands on its own between paragraphs, never wider than the picture itself.
private struct StandaloneImage: View {
    let url: URL
    let alt: String

    var body: some View {
        Group {
            if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: image.size.width)
            } else {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(alt).foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(.rect(cornerRadius: Tokens.plateRadius, style: .continuous))
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button("Save to Photos", systemImage: "square.and.arrow.down") {
                guard let image = UIImage(contentsOfFile: url.path) else { return }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
            Button("Copy", systemImage: "doc.on.doc") {
                if let image = UIImage(contentsOfFile: url.path) { UIPasteboard.general.image = image }
            }
            ShareLink(item: url)
        }
    }
}

struct ArticleVideo: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(.rect(cornerRadius: Tokens.plateRadius, style: .continuous))
            .task { player = AVPlayer(url: url) }
            .onDisappear {
                player?.pause()
                player = nil
            }
            .contextMenu {
                if url.isFileURL {
                    Button("Save to Photos", systemImage: "square.and.arrow.down") {
                        UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
                    }
                }
                ShareLink(item: url)
            }
    }
}
