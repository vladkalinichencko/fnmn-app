import AVKit
import FNMNCore
import SwiftUI
import Textual

struct BlockView: View, Equatable {
    let block: DocumentBlock
    let index: Int
    let baseURL: URL
    let mode: PlateMode
    let readShare: Double
    let markedReadThrough: Bool
    let annotations: [Annotation]
    let fold: HeadingFold
    var finds: [TextSpan] = []
    var activeFind: TextSpan?
    var spot: TextSpan?

    var body: some View {
        switch block {
        case let .heading(level, title):
            SectionHeading(index: index, level: level, title: title, fold: fold)
                .grayed(readShare)
        case let .text(markdown):
            PlateView(
                markdown: markdown, index: index, baseURL: baseURL, mode: mode,
                readShare: readShare, markedReadThrough: markedReadThrough, annotations: annotations,
                finds: finds, activeFind: activeFind, spot: spot
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

enum HeadingFold: Equatable {
    case none
    case open
    case closed(hidden: Int)
}

private struct SectionHeading: View {
    let index: Int
    let level: Int
    let title: String
    let fold: HeadingFold
    @Environment(ReaderCoordinator.self) private var reader

    var body: some View {
        HeadingView(level: level, title: title, fold: fold)
            .overlay {
                if fold != .none {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { reader.send(.toggleSection(index)) }
                }
            }
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = MarkedMarkdown.plainText(title, baseURL: nil)
                }
            }
    }
}

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
                    .transition(.blurReplace)
            }
            if fold != .none {
                DisclosureChevron(open: fold == .open, width: chevronWidth)
            }
        }
        .animation(.snappy(duration: 0.22), value: fold)
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
        return readerFont.font(style).bold()
    }
}

struct LeadImage: View {
    let url: URL

    var body: some View {
        FileImage(url: url, contentMode: .fill)
            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
        .clipShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
    }
}

extension EnvironmentValues {
    @Entry var plateTextWidth: CGFloat?
}

struct PlateView: View {
    @Environment(ReaderCoordinator.self) private var reader
    let markdown: String
    let index: Int
    let baseURL: URL
    let mode: PlateMode
    let readShare: Double
    let markedReadThrough: Bool
    let annotations: [Annotation]
    var finds: [TextSpan] = []
    var activeFind: TextSpan?
    var spot: TextSpan?
    @State private var drag: CGFloat = 0
    @State private var size = CGSize.zero
    @State private var noteHeight: CGFloat = 0

    @State private var side: Bool?
    @Environment(\.plateTextWidth) private var textWidth
    @AppStorage(ReaderAppearance.wordStartsKey) private var boldsWordStarts = false

    private var noting: Bool { mode == .noting(index) }
    private var open: Bool { side ?? noting }
    private var noteWidth: CGFloat { size.width * 0.58 }
    private var offset: CGFloat { (open ? -noteWidth : 0) + drag }
    private static let slide = Animation.spring(duration: 0.35, bounce: 0.2)
    private static let commit: CGFloat = 96
    private static let pullGap: CGFloat = 8

    var body: some View {
        ZStack(alignment: .trailing) {
            readButton
            MarginNote(saved: paragraphNote, active: noting && drag == 0, save: saveNote) { noteHeight = $0 }
                .frame(width: max(noteWidth - Tokens.gap, 0), height: size.height)
                .opacity(offset < 0 ? 1 : 0)
                .allowsHitTesting(noting)
            plate
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .offset(x: offset)
                .gesture(HorizontalPan(starts: { open ? $0 > 0 : true }, changed: dragged, ended: released))
        }
        .animation(Self.slide, value: open)
        .onChange(of: noting) { side = nil }
    }

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

    private func dragged(_ translation: CGFloat) {
        if open {
            drag = min(max(translation, 0), noteWidth)
        } else if translation < 0 {
            drag = max(translation, -noteWidth - 20)
        } else {
            drag = translation < Self.commit ? translation : Self.commit + (translation - Self.commit) * 0.35
        }
    }

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

    private var plate: some View {
        StructuredText(markdown, parser: MarkedMarkdown(baseURL: baseURL, marks: marks, width: textWidth, boldsWordStarts: boldsWordStarts, finds: finds, activeFind: activeFind, spot: spot))
            .id([AnyHashable(marks), AnyHashable(textWidth), AnyHashable(boldsWordStarts), AnyHashable(finds), AnyHashable(activeFind), AnyHashable(spot)])
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

struct NoteEdit: Equatable {
    private(set) var saved: String
    private(set) var draft: String
    private(set) var isEditing = false

    init(saved: String) {
        self.saved = saved
        self.draft = saved
    }

    mutating func begin() {
        isEditing = true
    }

    mutating func type(_ text: String) {
        draft = text
    }

    mutating func arrived(_ note: String) {
        guard !isEditing || draft == saved else {
            return
        }
        saved = note
        draft = note
    }

    mutating func finish() -> String? {
        isEditing = false
        guard draft != saved else {
            return nil
        }
        saved = draft
        return saved
    }

    mutating func abandon() -> String? {
        guard isEditing else {
            return nil
        }
        return finish()
    }
}

private struct MarginNote: View {
    let saved: String
    let active: Bool
    let save: (String) -> Void
    let measured: (CGFloat) -> Void
    @State private var note = NoteEdit(saved: "")
    @State private var overflow = Overflow()
    @State private var room: CGFloat = 0
    @FocusState private var focused: Bool
    @AppStorage(ReaderAppearance.fontKey) private var readerFont = ReaderFont.system

    var body: some View {
        Group {
            if active {
                ScrollView {
                    TextField("Note", text: draftBinding, axis: .vertical)
                        .focused($focused)
                        .onAppear { focused = saved.isEmpty }
                        .modifier(NoteLayout(font: readerFont.font(.callout)))
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
                Text(note.draft.isEmpty ? "Note" : note.draft)
                    .foregroundStyle(note.draft.isEmpty ? .tertiary : .primary)
                    .modifier(NoteLayout(font: readerFont.font(.callout)))
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        overflow = Overflow(below: height > room + 1, text: height)
                    }
                    .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                    .clipped()
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { room = $0 }
        .mask(fade)
        .onChange(of: overflow.text) { measured(overflow.text - 2 * Tokens.tilePadding) }
        .onAppear {
            note = NoteEdit(saved: saved)
            if active {
                note.begin()
            }
        }
        .onChange(of: saved) { note.arrived(saved) }
        .onChange(of: active) {
            guard active else {
                focused = false
                if let text = note.finish() {
                    save(text)
                }
                return
            }
            note.begin()
        }
        .onDisappear {
            if let text = note.abandon() {
                save(text)
            }
        }
    }

    private var draftBinding: Binding<String> {
        Binding(get: { note.draft }, set: { note.type($0) })
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

    private struct NoteLayout: ViewModifier {
        let font: Font

        func body(content: Content) -> some View {
            content
                .font(font)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Tokens.tilePadding)
        }
    }

    private struct Overflow: Equatable {
        var above = false
        var below = false
        var text: CGFloat = 0
    }
}

private struct StandaloneImage: View {
    let url: URL
    let alt: String
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

struct ArticleVideo: View {
    let url: URL
    @State private var poster = Poster.loading

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
