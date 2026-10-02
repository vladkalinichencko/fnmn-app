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
    /// How much of the block is read, from its top: all of it once scrolled past the top or before the "read through
    /// here" mark, the part above the reading line while the line stands in it.
    let readShare: Double
    /// The "read through here" mark stands on this paragraph.
    let markedReadThrough: Bool
    /// Highlights and notes on this block.
    let annotations: [Annotation]
    /// What a heading does when tapped; `.none` for every other block.
    let fold: HeadingFold

    var body: some View {
        switch block {
        case let .heading(level, title):
            SectionHeading(index: index, level: level, title: title, fold: fold)
                .grayed(readShare)
        case let .text(markdown):
            PlateView(
                markdown: markdown, index: index, baseURL: baseURL, mode: mode,
                readShare: readShare, markedReadThrough: markedReadThrough, annotations: annotations
            )
        case let .image(alt, path):
            StandaloneImage(url: resolve(path), alt: alt)
        case let .video(path):
            ArticleVideo(url: resolve(path))
        case let .interactive(url, selector):
            LiveCropView(url: resolve(url.absoluteString), selector: selector)
        }
    }

    private func resolve(_ path: String) -> URL {
        if let url = URL(string: path), url.scheme != nil { return url }
        return baseURL.appending(path: path)
    }
}

extension View {
    /// Grays the read share of a block from its top, at once, even when the change comes inside another animation
    /// such as a plate sliding back. Every block keeps the mask, read or not, so reading on does not rebuild it.
    func grayed(_ readShare: Double) -> some View {
        mask {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Color.black.opacity(Tokens.readOpacity)
                        .frame(height: geometry.size.height * min(max(readShare, 0), 1))
                    Color.black
                }
                .transaction(value: readShare) { $0.animation = nil }
            }
        }
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
    @Environment(ReaderCoordinator.self) private var reader

    var body: some View {
        HeadingView(level: level, title: title, fold: fold)
            // Over the title, which would otherwise take the touch: the whole heading is the button.
            .overlay {
                if fold != .none {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { reader.send(.toggleSection(index)) }
                }
            }
            // A heading is not selected in parts; a long press copies all of it.
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = MarkedMarkdown.plainText(title, baseURL: nil)
                }
            }
    }
}

/// A heading on the page. A heading with a section under it shows a chevron that turns when the section opens, and
/// how many blocks it hides while it is closed.
struct HeadingView: View {
    let level: Int
    let title: String
    var fold = HeadingFold.none
    @AppStorage(ReaderAppearance.fontKey) private var readerFont = ReaderFont.system
    @ScaledMetric(relativeTo: .subheadline) private var chevronWidth: CGFloat = 18

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
                    // A turn leaves the layout as it was, so the chevron gets the width it needs lying down; past
                    // the heading's edge the gray mask would cut it off.
                    .frame(width: chevronWidth)
            }
        }
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
    let readShare: Double
    let markedReadThrough: Bool
    let annotations: [Annotation]
    /// How far the finger has moved the plate from where the mode puts it; zero whenever no finger is on it.
    @State private var drag: CGFloat = 0
    @State private var size = CGSize.zero
    /// The height of the note's text, which the tab on the plate's edge follows.
    @State private var noteHeight: CGFloat = 0

    /// Where the last swipe left the plate, until the mode catches up with it.
    @State private var side: Bool?

    private var noting: Bool { mode == .noting(index) }
    /// Whether the plate stands aside. The swipe decides this at once and the mode follows a moment later, so a
    /// finger always moves the plate from where it is on the screen, however far behind the mode is.
    private var open: Bool { side ?? noting }
    /// How far the plate moves aside for its note: a little over half its width.
    private var noteWidth: CGFloat { size.width * 0.58 }
    /// The plate rests aside exactly while it is open; the finger only adds to it.
    private var offset: CGFloat { (open ? -noteWidth : 0) + drag }
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
                .gesture(HorizontalPan(starts: { open ? $0 > 0 : true }, changed: dragged, ended: released))
        }
        .animation(Self.slide, value: open)
        .onChange(of: noting) { side = nil }
    }

    /// The button the plate uncovers as it is pulled right, as wide as the pull; it takes hold, with a tap of
    /// feedback, once the plate has gone far enough for letting go to mark. Its icon stands over a short caption, so
    /// both fit in the width the pull reaches before it takes hold.
    private var readButton: some View {
        let pull = max(offset, 0)
        return Color.accentColor
            .overlay {
                VStack(spacing: 3) {
                    Image(systemName: markedReadThrough ? "arrow.uturn.backward" : "checkmark")
                        .font(.body.weight(.semibold))
                    Text(markedReadThrough ? "Unmark" : "Read to Here")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .fixedSize()
                .opacity(min(pull / 60, 1))
                .scaleEffect(pull >= Self.commit ? 1.06 : 1)
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
        if open {
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
            if open, thrown > noteWidth / 2 {
                side = false
                reader.send(.plate(.done))
            } else if !open, thrown < -noteWidth / 2 {
                side = true
                reader.send(.plate(.note(index)))
            } else if !open, thrown > Self.commit {
                reader.send(.readThrough(markedReadThrough ? nil : index))
            }
        }
    }

    /// A selection stays inside its plate. What is read grays in the text; the glass stays as it is.
    private var plate: some View {
        StructuredText(markdown, parser: MarkedMarkdown(baseURL: baseURL, marks: marks))
            // StructuredText parses again only when the Markdown changes; new marks need a new parse.
            .id(marks)
            .textual.overflowMode(.wrap)
            .plateMarkdownStyles()
            .textual.textSelection(.enabled)
            .environment(\.textualSelectionMenu, selectionMenu)
            .padding(Tokens.tilePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .grayed(readShare)
            .plate(cornerRadius: Tokens.plateRadius)
            .overlay(alignment: .topTrailing) { noteMark }
            .contentShape(.interaction, .rect(cornerRadius: Tokens.plateRadius, style: .continuous))
            .gesture(TapGesture().onEnded { side = false; reader.send(.plate(.done)) }, isEnabled: open)
            .sensoryFeedback(.impact(weight: .light), trigger: marks)
            .sensoryFeedback(.selection, trigger: markedReadThrough)
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

    /// The edit menu of a selection in this plate: each mark or its removal, ChatGPT, and saving the pictures inside
    /// it. Keyed by the paragraph and its marks, so it changes only when they do.
    private var selectionMenu: TextSelectionMenu {
        let reader = reader, index = index, annotations = annotations, text = plainText
        return TextSelectionMenu(key: [AnyHashable(reader.materialID), AnyHashable(index), AnyHashable(annotations)]) { selected in
            var items: [UIMenuElement] = []
            if !selected.text.isEmpty {
                let target = reader.target(index, text: text, quote: selected.text)
                items += annotationCommands(annotations, at: target).map { command in
                    UIAction(title: command.title, image: UIImage(systemName: command.systemImage)) { _ in
                        reader.send(.mark(command, target))
                    }
                }
                items.append(UIAction(title: "Ask ChatGPT", image: UIImage(systemName: "bubble.left.and.text.bubble.right")) { _ in
                    reader.send(.ask(selected.text))
                })
                items.append(UIAction(title: "Copy as Prompt", image: UIImage(systemName: "text.quote")) { _ in
                    reader.send(.copyPrompt(selected.text))
                })
            }
            if !selected.images.isEmpty {
                let title = selected.images.count == 1 ? "Save Picture to Photos" : "Save \(selected.images.count) Pictures to Photos"
                items.append(UIAction(title: title, image: UIImage(systemName: "square.and.arrow.down")) { _ in
                    for image in selected.images { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) }
                })
            }
            return items
        }
    }

    private var marks: [QuoteMark] {
        annotations.flatMap(\.marks)
    }

    private var paragraphNote: String {
        annotations.first { !$0.note.isEmpty }?.note ?? ""
    }

    private var plainText: String {
        MarkedMarkdown.plainText(markdown, baseURL: baseURL)
    }

    private func saveNote(_ text: String) {
        reader.send(.note(text, reader.target(index, text: plainText)))
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
                    // Without a minimum the frame grows to the fixed text, so a long note would show whole past its paragraph.
                    .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
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

/// A picture that stands on its own between paragraphs, never wider than the picture itself. A tap opens it on the
/// whole screen.
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
                    Loading()
                        .frame(height: Tokens.embedHeight)
                        .plate(cornerRadius: Tokens.plateRadius)
                }
            }
        }
        .clipShape(.rect(cornerRadius: Tokens.plateRadius, style: .continuous))
        .opensMedia(url)
        .frame(maxWidth: .infinity)
    }
}

/// A video in the text is its first frame under a play button; a tap plays it on the whole screen.
struct ArticleVideo: View {
    let url: URL
    @State private var poster = Poster.loading

    /// The first frame, shown before the video plays; a video whose frame cannot be read plays all the same.
    private enum Poster {
        case loading
        case frame(UIImage)
        case none
    }

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                switch poster {
                case .loading: Loading()
                case let .frame(frame): Image(uiImage: frame).resizable().scaledToFit()
                case .none: EmptyView()
                }
            }
            .overlay {
                if case .loading = poster {} else {
                    Image(systemName: "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .padding(18)
                        .glassEffect(.regular, in: .circle)
                }
            }
            .clipShape(.rect(cornerRadius: Tokens.plateRadius, style: .continuous))
            .plate(cornerRadius: Tokens.plateRadius)
            .opensMedia(url)
            .task { poster = await Self.firstFrame(of: url).map(Poster.frame) ?? .none }
    }

    @concurrent
    private static func firstFrame(of url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        guard let (image, _) = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: image)
    }
}
