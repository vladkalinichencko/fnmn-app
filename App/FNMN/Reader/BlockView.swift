import AVKit
import FNMNCore
import SwiftUI
import Textual

/// The one place that decides how each kind of block is drawn. It holds only values, so SwiftUI compares it
/// and skips its body when nothing it shows has changed; actions go to the `ReaderCoordinator` in the environment.
struct BlockView: View, Equatable {
    let block: DocumentBlock
    let index: Int
    let baseURL: URL
    let mode: PlateMode
    /// The paragraph scrolled past the top, or lies before the "read through here" mark.
    let read: Bool
    /// The "read through here" mark stands on this paragraph.
    let markedReadThrough: Bool
    /// Highlights and notes on this block.
    let annotations: [Annotation]
    /// The number of blocks under this heading when the document is folded; nil while it is open.
    let folded: Int?
    /// A heading whose section is read to its last block, by the reading place or the "read through here" mark.
    let sectionRead: Bool

    var body: some View {
        switch block {
        case let .heading(level, title):
            SectionHeading(index: index, level: level, title: title, folded: folded, read: sectionRead)
        case let .text(markdown):
            PlateView(
                markdown: markdown, index: index, baseURL: baseURL, mode: mode,
                read: read, markedReadThrough: markedReadThrough, annotations: annotations
            )
        case let .image(alt, path):
            StandaloneImage(url: resolve(path), alt: alt)
        case let .video(path):
            ArticleVideo(url: resolve(path))
        case let .interactive(url, selector):
            LiveCropView(url: url, selector: selector)
        }
    }

    private func resolve(_ path: String) -> URL {
        if let url = URL(string: path), url.scheme != nil { return url }
        return baseURL.appending(path: path)
    }
}

/// While fingers pinch in, the blocks the pinch will fold away, paragraphs or headings, begin to rise into
/// the block they fold into, as far as the fingers have gone.
struct PinchFold: ViewModifier {
    let index: Int
    /// Whether the next pinch in folds this block away, and the block above it that stays, which it folds into.
    let folding: Bool
    let parent: Int?
    @Environment(PinchScale.self) private var pinch

    func body(content: Content) -> some View {
        let amount = folding ? min(max(1 - pinch.value, 0), 0.6) / 0.6 * 0.5 : 0
        content.modifier(FoldIntoHeading(index: index, parent: parent, amount: amount))
    }
}

/// A block folding into the one above it that stays: it rises toward that block's lower edge, flattening and
/// fading as it goes, so a whole section gathers under its heading. At 1 it is folded away; the same effect
/// carries the fold's transition and the pinch that leads to it.
struct FoldIntoHeading: ViewModifier {
    let index: Int
    let parent: Int?
    let amount: Double
    @Environment(PinchScale.self) private var pinch

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1 - 0.06 * amount, y: 1 - 0.4 * amount, anchor: .top)
            .offset(y: -pinch.rise(of: index, into: parent) * amount)
            .opacity(1 - amount)
    }
}

extension AnyTransition {
    static func fold(_ index: Int, into parent: Int?) -> AnyTransition {
        .modifier(
            active: FoldIntoHeading(index: index, parent: parent, amount: 1),
            identity: FoldIntoHeading(index: index, parent: parent, amount: 0)
        )
    }
}

/// Tapping a heading in the folded document opens the text at it.
private struct SectionHeading: View {
    let index: Int
    let level: Int
    let title: String
    let folded: Int?
    let read: Bool
    @Environment(ReaderCoordinator.self) private var reader

    var body: some View {
        HeadingView(level: level, title: title, folded: folded, read: read)
            .onTapGesture { reader.send(.openSection(index)) }
    }
}

/// A heading on the page. Open and folded it is the same view, so it slides to its place in the outline
/// instead of fading out and in; folded, it sits closer and shows how many blocks it holds. It grays once its section is read.
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
        .foregroundStyle(read ? .secondary : .primary)
        .animation(.easeInOut(duration: 0.4), value: read)
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
        FileImage(url: url, contentMode: .fill)
            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
        .clipShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
    }
}

/// A paragraph, list, quote, table or code block on its own rounded plate.
/// Dragging it left uncovers its margin note, which lies under the plate all along; the system's leading swipe marks "read to here".
struct PlateView: View {
    @Environment(ReaderCoordinator.self) private var reader
    let markdown: String
    let index: Int
    let baseURL: URL
    let mode: PlateMode
    let read: Bool
    let markedReadThrough: Bool
    let annotations: [Annotation]
    @State private var drag: CGFloat = 0
    @State private var size = CGSize.zero
    /// The height of the note's text, which the tab on the plate's edge follows.
    @State private var noteHeight: CGFloat = 0
    /// Whether the plate stands aside for the note. It follows the mode in its own animation, whose end tells
    /// when the note may come up for touches or hide again.
    @State private var open = false
    /// The note shows under the plate from the first move of a swipe until the plate is back over it.
    @State private var uncovered = false
    /// Once the plate has moved aside, the note is lifted above the row so touches reach it.
    @State private var raised = false

    private var noting: Bool { mode == .noting(index) }
    /// How far the plate moves aside for its note: a little over half its width.
    private var noteWidth: CGFloat { size.width * 0.58 }
    private var offset: CGFloat { (open ? -noteWidth : 0) + drag }
    private static let slide = Animation.spring(duration: 0.35, bounce: 0.2)

    /// The note lies under the plate, and the plate slides off it. The note is laid out even while hidden, so the
    /// tab on the plate knows its height.
    var body: some View {
        ZStack(alignment: .trailing) {
            plate
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .zIndex(1)
            MarginNote(saved: paragraphNote, active: noting, save: saveNote) { noteHeight = $0 }
                .frame(width: max(noteWidth - Tokens.gap, 0), height: size.height)
                .opacity(uncovered ? 1 : 0)
                .allowsHitTesting(raised)
                .zIndex(raised ? 2 : 0)
        }
        // A plate scrolled back into view while its note is open is built aside at once.
        .onAppear { open = noting; uncovered = noting; raised = noting }
        .onChange(of: noting) { _, now in
            if now { withoutAnimation { uncovered = true } } else { raised = false }
            withAnimation(Self.slide) { open = now } completion: { settled() }
        }
    }

    private func dragged(_ translation: CGFloat) {
        guard mode == .reading || noting else { return }
        uncovered = true
        drag = noting ? max(translation, 0) : max(min(translation, 0), -noteWidth - 20)
    }

    /// The drag and the mode change in one animation, so the plate goes straight from under the finger to where
    /// the mode puts it instead of springing back to its place and out again.
    private func released(_ translation: CGFloat, _ velocity: CGFloat) {
        withAnimation(Self.slide) {
            drag = 0
            if noting {
                if translation > 60 || velocity > 500 { reader.send(.plate(.done)) }
            } else if translation < -60 || velocity < -500 {
                reader.send(.plate(.note(index)))
            }
        } completion: {
            settled()
        }
    }

    /// Where the plate came to rest: aside, the note comes up for touches; back in place, it hides.
    private func settled() {
        guard drag == 0 else { return }
        raised = open
        uncovered = open
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
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
            .opacity(read && mode == .reading ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.4), value: read)
            // The menu lifts the plate by this shape too; by the frame it would lift the square corners around the glass.
            .contentShape([.interaction, .contextMenuPreview], .rect(cornerRadius: Tokens.plateRadius, style: .continuous))
            .gesture(TapGesture().onEnded { reader.send(.plate(.toggle(index))) }, isEnabled: isTicking)
            .gesture(TapGesture().onEnded { reader.send(.plate(.done)) }, isEnabled: noting)
            .contextMenu { if mode == .reading { menu } }
            // Inside the system's swipe, which places the row itself and would undo an offset put around it.
            .offset(x: offset)
            // Leftward belongs to the note; rightward to the system's swipe, or to closing an open note.
            .gesture(HorizontalPan(starts: { noting ? $0 > 0 : $0 < 0 }, changed: dragged, ended: released))
            .swipeActions(edge: .leading) {
                if mode == .reading {
                    Button(markedReadThrough ? "Unmark" : "Read to Here", systemImage: markedReadThrough ? "arrow.uturn.backward" : "checkmark") {
                        reader.send(.readThrough(markedReadThrough ? nil : index))
                    }
                    .tint(.accentColor)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: marks)
            .sensoryFeedback(.selection, trigger: markedReadThrough)
    }

    @ViewBuilder
    private var menu: some View {
        let text = plainText
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
        let target = reader.target(index, text: text)
        ForEach(annotationCommands(annotations, at: target), id: \.title) { command in
            Button(command.title, systemImage: command.systemImage) { reader.send(.mark(command, target)) }
        }
        Button("Select Text", systemImage: "character.cursor.ibeam") { reader.send(.plate(.selectText(index))) }
        Button("Select Paragraphs", systemImage: "checklist") { reader.send(.plate(.selectParagraphs(from: index))) }
        Button("Add Note", systemImage: "note.text") { reader.send(.plate(.note(index))) }
        Button("Ask ChatGPT", systemImage: "bubble.left.and.text.bubble.right") { reader.send(.ask(text)) }
        Button("Copy as Prompt", systemImage: "text.quote") { reader.send(.copyPrompt(text)) }
        let pictures = ArticleBody.imagePaths(in: markdown).map { baseURL.appending(path: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        ForEach(Array(pictures.enumerated()), id: \.offset) { number, picture in
            Button(pictures.count == 1 ? "Save Picture to Photos" : "Save Picture \(number + 1) to Photos", systemImage: "square.and.arrow.down") {
                guard let image = UIImage(contentsOfFile: picture.path) else { return }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
    }

    /// Keyed by the paragraph and its marks: the menu changes only when they do.
    private var selectionMenu: TextSelectionMenu {
        let text = plainText
        let reader = reader
        let annotations = annotations
        let index = index
        return TextSelectionMenu(key: [AnyHashable(reader.materialID), AnyHashable(index), AnyHashable(annotations)]) { selected in
            let target = reader.target(index, text: text, quote: selected)
            let marks = annotationCommands(annotations, at: target).map { command in
                UIAction(title: command.title, image: UIImage(systemName: command.systemImage)) { _ in reader.send(.mark(command, target)) }
            }
            let ask = UIAction(title: "Ask ChatGPT", image: UIImage(systemName: "bubble.left.and.text.bubble.right")) { _ in reader.send(.ask(selected)) }
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

    /// A tab on the right edge of a plate that has a note, as tall as the note's text within the plate; the note
    /// itself shows when the plate is pulled aside.
    @ViewBuilder
    private var noteMark: some View {
        if !paragraphNote.isEmpty, !uncovered {
            Capsule()
                .fill(.tint)
                .frame(width: 4, height: min(max(noteHeight, 22), max(size.height - 2 * Tokens.tilePadding - 4, 22)))
                .padding(.top, Tokens.tilePadding + 2)
                .offset(x: 2)
        }
    }

    private var isTicking: Bool {
        if case .selectingParagraphs = mode { true } else { false }
    }

    private var marks: [ParagraphQuoteMark] {
        annotations.compactMap { annotation in
            guard let mark = annotation.mark, !annotation.quote.isEmpty else { return nil }
            return ParagraphQuoteMark(quote: annotation.quote, mark: mark)
        }
    }

    /// The note on the whole paragraph. It is stored with the paragraph's text as its quote, so the shelf can show both.
    private var paragraphNote: String {
        let notes = annotations.filter { !$0.note.isEmpty }
        guard !notes.isEmpty else { return "" }
        let text = plainText
        return notes.first { $0.quote.isEmpty || $0.quote == text }?.note ?? ""
    }

    private var plainText: String {
        MarkedMarkdown.plainText(markdown, baseURL: baseURL)
    }

    private func saveNote(_ text: String) {
        let paragraph = plainText
        reader.send(.note(text, reader.target(index, text: paragraph, quote: paragraph)))
    }
}

/// A note in the margin beside its paragraph: plain text on the page, no frame, saved when it closes.
/// It is as tall as its paragraph; a longer note scrolls, fading out at the edge it continues past.
/// The scroll view stays the same while the note opens and closes, so the note never swaps for another view;
/// inside it, every plate on screen carries plain text, and only the open note an editor in the same place.
private struct MarginNote: View {
    let saved: String
    let active: Bool
    let save: (String) -> Void
    /// The height of the note's text, without the room around it.
    let measured: (CGFloat) -> Void
    @State private var draft = ""
    @State private var overflow = Overflow()
    @FocusState private var focused: Bool
    @AppStorage(ReaderAppearance.fontKey) private var readerFont = ReaderFont.system

    var body: some View {
        ScrollView {
            Group {
                if active {
                    TextField("Note", text: $draft, axis: .vertical)
                        .focused($focused)
                        .onAppear { focused = saved.isEmpty }
                } else {
                    Text(draft.isEmpty ? "Note" : draft)
                        .foregroundStyle(draft.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.system(.callout, design: readerFont.design))
            .padding(.vertical, Tokens.tilePadding)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(!active)
        .onScrollGeometryChange(for: Overflow.self) { geometry in
            Overflow(
                above: geometry.contentOffset.y > 1,
                below: geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1,
                text: geometry.contentSize.height - 2 * Tokens.tilePadding
            )
        } action: { _, new in
            overflow = new
            measured(new.text)
        }
        .mask(fade)
        .onAppear { draft = saved }
        .onChange(of: saved) { draft = saved }
        .onChange(of: active) {
            guard !active else { return }
            focused = false
            if draft != saved { save(draft) }
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
        var text: CGFloat = 0
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

/// A picture that stands on its own between paragraphs, never wider than the picture itself.
private struct StandaloneImage: View {
    let url: URL
    let alt: String
    /// The picture's own size, read from its file header before the block is laid out: a picture that took its
    /// height only after it appeared would push the text below it down while scrolling up.
    @State private var natural: CGSize?

    init(url: URL, alt: String) {
        self.url = url
        self.alt = alt
        _natural = State(initialValue: url.isFileURL ? ImageFiles.headerSize(of: url) : nil)
    }

    var body: some View {
        Group {
            if url.isFileURL {
                if let natural {
                    FileImage(url: url, contentMode: .fit)
                        .aspectRatio(natural, contentMode: .fit)
                        .frame(maxWidth: natural.width)
                } else {
                    Text(alt).foregroundStyle(.secondary)
                }
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
