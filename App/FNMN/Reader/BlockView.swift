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
    /// What a heading does when tapped; `.none` for every other block.
    let fold: HeadingFold

    var body: some View {
        switch block {
        case let .heading(level, title):
            SectionHeading(index: index, level: level, title: title, fold: fold, read: read)
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

/// Whether a heading has a section under it to close up, and whether it has.
enum HeadingFold: Equatable {
    case none
    case open
    /// Closed, with the number of blocks it hides.
    case closed(hidden: Int)
}

/// A heading whose tap closes its section up under it or opens it again.
private struct SectionHeading: View {
    let index: Int
    let level: Int
    let title: String
    let fold: HeadingFold
    let read: Bool
    @Environment(ReaderCoordinator.self) private var reader

    var body: some View {
        HeadingView(level: level, title: title, fold: fold, read: read)
            // Over the title, which would otherwise take the touch: the whole heading is the button.
            .overlay {
                if fold != .none {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { reader.send(.toggleSection(index)) }
                }
            }
    }
}

/// A heading on the page. A heading with a section under it shows a chevron that turns when the section opens, and
/// how many blocks it hides while it is closed. It grays once it is read, as a paragraph does.
struct HeadingView: View {
    let level: Int
    let title: String
    var fold = HeadingFold.none
    var read = false
    @AppStorage(ReaderAppearance.fontKey) private var readerFont = ReaderFont.system

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            InlineText(markdown: title, syntaxExtensions: [.math])
                .font(font)
                .frame(maxWidth: .infinity, alignment: .leading)
            if case let .closed(hidden) = fold, hidden > 0 {
                Text(hidden, format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if fold != .none {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(fold == .open ? 90 : 0))
            }
        }
        .opacity(read ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.4), value: read)
        .padding(.top, level <= 2 ? Tokens.gap : 4)
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
/// Dragging it left uncovers its margin note, which lies under the plate all along; dragging it right far enough
/// marks "read to here", with a tap of feedback where the mark takes hold.
struct PlateView: View {
    @Environment(ReaderCoordinator.self) private var reader
    let markdown: String
    let index: Int
    let baseURL: URL
    let mode: PlateMode
    let read: Bool
    let markedReadThrough: Bool
    let annotations: [Annotation]
    /// How far the finger has moved the plate from where the mode puts it; zero whenever no finger is on it.
    @State private var drag: CGFloat = 0
    @State private var size = CGSize.zero
    /// The height of the note's text, which the tab on the plate's edge follows.
    @State private var noteHeight: CGFloat = 0

    private var noting: Bool { mode == .noting(index) }
    /// How far the plate moves aside for its note: a little over half its width.
    private var noteWidth: CGFloat { size.width * 0.58 }
    /// The mode alone says where the plate rests, aside exactly while its note is open; the finger only adds to it.
    private var offset: CGFloat { (noting ? -noteWidth : 0) + drag }
    private static let slide = Animation.spring(duration: 0.35, bounce: 0.2)
    /// How far the plate is pulled right before letting go marks "read to here".
    private static let commit: CGFloat = 96
    /// The gap between the plate and the mark's button as the plate is pulled.
    private static let pullGap: CGFloat = 8

    /// The note lies under the glass plate, blurred by it, and the plate slides off it; touches on the uncovered note
    /// reach the note. The note is editable only while the plate stands aside: an editor is a UIKit view, which
    /// draws over SwiftUI's own drawing, so under a moving plate it would show on top of the glass. Pulled right,
    /// the plate uncovers the "read to here" button instead.
    var body: some View {
        ZStack(alignment: .trailing) {
            readButton
            MarginNote(saved: paragraphNote, active: noting && drag == 0, save: saveNote) { noteHeight = $0 }
                .frame(width: max(noteWidth - Tokens.gap, 0), height: size.height)
                // At rest the note's corners would show past the plate's rounded ones.
                .opacity(offset < 0 ? 1 : 0)
                .allowsHitTesting(noting)
            plate
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .offset(x: offset)
                // Leftward opens the note while reading and rightward closes it; rightward while reading pulls
                // out the "read to here" button.
                .gesture(HorizontalPan(starts: { noting ? $0 > 0 : mode == .reading }, changed: dragged, ended: released))
        }
        .animation(Self.slide, value: noting)
    }

    /// The button the plate uncovers as it is pulled right, as wide as the pull; it takes hold, with a tap of
    /// feedback, once the plate has gone far enough for letting go to mark.
    private var readButton: some View {
        let pull = max(offset, 0)
        let label = markedReadThrough ? "Unmark" : "Read to Here"
        return Color.accentColor
            .overlay(alignment: .leading) {
                Label(label, systemImage: markedReadThrough ? "arrow.uturn.backward" : "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.leading, 20)
                    .opacity(min(pull / 60, 1))
                    .scaleEffect(pull >= Self.commit ? 1.06 : 1, anchor: .leading)
                    .animation(.snappy, value: pull >= Self.commit)
            }
            .frame(width: max(pull - Self.pullGap, 0), height: size.height)
            .clipShape(.rect(cornerRadius: Tokens.plateRadius, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(pull > 0 ? 1 : 0)
            .allowsHitTesting(false)
            .sensoryFeedback(.impact(weight: .medium), trigger: pull >= Self.commit) { _, taken in taken }
    }

    /// The plate follows the finger: left up to a little past the note's edge, right with growing resistance once the
    /// mark would take hold, and back toward the note's side while it is open, never past where it rests.
    private func dragged(_ translation: CGFloat) {
        if noting {
            drag = min(max(translation, 0), noteWidth)
        } else if translation < 0 {
            drag = max(translation, -noteWidth - 20)
        } else {
            drag = translation < Self.commit ? translation : Self.commit + (translation - Self.commit) * 0.35
        }
    }

    /// The plate changes sides only when it has gone, or is thrown, past half the note's width, and marks only past
    /// the pull; otherwise it goes back to where the mode keeps it. The drag and the mode change in one animation,
    /// so the plate goes straight from under the finger to its place.
    private func released(_ translation: CGFloat, _ velocity: CGFloat) {
        let thrown = translation + velocity * 0.2
        withAnimation(Self.slide) {
            drag = 0
            if noting, thrown > noteWidth / 2 {
                reader.send(.plate(.done))
            } else if !noting, thrown < -noteWidth / 2 {
                reader.send(.plate(.note(index)))
            } else if !noting, thrown > Self.commit {
                reader.send(.readThrough(markedReadThrough ? nil : index))
            }
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
            .overlay {
                // Over the text, which would otherwise take the touch: the whole plate is the button.
                if isTicking {
                    Color.clear
                        .contentShape(.rect(cornerRadius: Tokens.plateRadius, style: .continuous))
                        .onTapGesture { reader.send(.plate(.toggle(index))) }
                }
            }
            .overlay(alignment: .topTrailing) {
                if let tick { tick } else { noteMark }
            }
            .opacity(read && mode == .reading ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.4), value: read)
            // The menu lifts the plate by this shape too; by the frame it would lift the square corners around the glass.
            .contentShape([.interaction, .contextMenuPreview], .rect(cornerRadius: Tokens.plateRadius, style: .continuous))
            .gesture(TapGesture().onEnded { reader.send(.plate(.done)) }, isEnabled: noting)
            .contextMenu { if mode == .reading { menu } }
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
                .allowsHitTesting(false)
        )
    }

    /// A tab on the right edge of a plate that has a note, as tall as the note's text within the plate; the note
    /// itself shows when the plate is pulled aside.
    @ViewBuilder
    private var noteMark: some View {
        if !paragraphNote.isEmpty, offset == 0 {
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
/// It is as tall as its paragraph; a longer note fades out at its lower edge and scrolls while it is edited.
/// Closed, it is SwiftUI's own text, which the glass plate over it blurs. Open, it is an editor in a scroll view,
/// both UIKit views that draw over everything SwiftUI draws; the text keeps the same place in either.
private struct MarginNote: View {
    let saved: String
    let active: Bool
    let save: (String) -> Void
    /// The height of the note's text, without the room around it.
    let measured: (CGFloat) -> Void
    @State private var draft = ""
    @State private var overflow = Overflow()
    /// The height the paragraph gives the note.
    @State private var room: CGFloat = 0
    @FocusState private var focused: Bool
    @AppStorage(ReaderAppearance.fontKey) private var readerFont = ReaderFont.system

    var body: some View {
        Group {
            if active {
                ScrollView {
                    TextField("Note", text: $draft, axis: .vertical)
                        .focused($focused)
                        .onAppear { focused = saved.isEmpty }
                        .modifier(NoteLayout(design: readerFont.design))
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .onScrollGeometryChange(for: Overflow.self) { geometry in
                    Overflow(
                        above: geometry.contentOffset.y > 1,
                        below: geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1,
                        text: geometry.contentSize.height
                    )
                } action: { _, new in overflow = new }
            } else {
                Text(draft.isEmpty ? "Note" : draft)
                    .foregroundStyle(draft.isEmpty ? .tertiary : .primary)
                    .modifier(NoteLayout(design: readerFont.design))
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        overflow = Overflow(below: height > room + 1, text: height)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { room = $0 }
        .mask(fade)
        .onChange(of: overflow.text) { measured(overflow.text - 2 * Tokens.tilePadding) }
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

    /// The closed text and the editor stand in the same place, so the note does not move when it opens.
    private struct NoteLayout: ViewModifier {
        let design: Font.Design

        func body(content: Content) -> some View {
            content
                .font(.system(.callout, design: design))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Tokens.tilePadding)
        }
    }

    private struct Overflow: Equatable {
        var above = false
        var below = false
        /// The height of the text with the room above and below it.
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
