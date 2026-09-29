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
    let actions: ParagraphActions
    let send: (PlateAction) -> Void
    let openSection: (Int) -> Void

    var body: some View {
        switch block {
        case let .heading(level, title):
            HeadingView(level: level, title: title)
                .onTapGesture { openSection(index) }
        case let .text(markdown):
            PlateView(markdown: markdown, index: index, baseURL: baseURL, current: current, mode: mode, actions: actions, send: send)
                .modifier(PinchFade(pinch: pinch))
        case let .image(alt, path):
            StandaloneImage(url: resolve(path), alt: alt)
                .modifier(PinchFade(pinch: pinch))
        case let .video(path):
            ArticleVideo(url: resolve(path))
                .modifier(PinchFade(pinch: pinch))
        case let .interactive(url, selector):
            LiveCropView(url: url, selector: selector)
                .modifier(PinchFade(pinch: pinch))
        }
    }

    private func resolve(_ path: String) -> URL {
        if let url = URL(string: path), url.scheme != nil { return url }
        return baseURL.appending(path: path)
    }
}

/// While fingers pinch in, everything but the headings shrinks and fades with them.
private struct PinchFade: ViewModifier {
    let pinch: CGFloat

    func body(content: Content) -> some View {
        let progress = min(max(1 - pinch, 0), 0.6) / 0.6
        content
            .scaleEffect(1 - progress * 0.08, anchor: .top)
            .opacity(1 - progress * 0.8)
    }
}

struct HeadingView: View {
    let level: Int
    let title: String
    @AppStorage(ReaderAppearance.fontKey) private var readerFont = ReaderFont.system

    var body: some View {
        InlineText(markdown: title, syntaxExtensions: [.math])
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// A paragraph, list, quote, table or code block on its own rounded plate.
struct PlateView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    let markdown: String
    let index: Int
    let baseURL: URL
    let current: Int?
    let mode: PlateMode
    let actions: ParagraphActions
    let send: (PlateAction) -> Void

    var body: some View {
        let note = paragraphNote
        let layout = sizeClass == .regular
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Tokens.gap))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        layout {
            plate
            if mode == .noting(index) || !note.isEmpty {
                MarginNote(saved: note, editing: mode == .noting(index), save: saveNote, edit: { send(.note(index)) })
                    .frame(width: sizeClass == .regular ? 220 : nil, alignment: .leading)
            }
        }
    }

    private var plate: some View {
        StructuredText(markdown, parser: MarkedMarkdown(baseURL: baseURL, marks: marks))
            // StructuredText parses again only when the Markdown changes; new marks need a new parse.
            .id(marks)
            .textual.overflowMode(.wrap)
            .modifier(TextSelection(isOn: mode == .selectingText(index)))
            .environment(\.textualSelectionMenu, mode == .selectingText(index) ? selectionMenu : nil)
            .padding(Tokens.tilePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .plate(cornerRadius: Tokens.plateRadius)
            .overlay(alignment: .topTrailing) { tick }
            .opacity(isRead && mode == .reading ? 0.55 : 1)
            .contentShape(.rect(cornerRadius: Tokens.plateRadius, style: .continuous))
            .modifier(TickOnTap(isOn: isTicking) { send(.toggle(index)) })
            .contextMenu { if mode == .reading { menu } }
            .swipeActions(edge: .leading) {
                let marked = library.snapshot.readThrough[actions.materialID] == index
                Button(marked ? "Unmark" : "Read to Here", systemImage: marked ? "arrow.uturn.backward" : "checkmark") {
                    Task { await library.apply(.readThrough(piece: marked ? nil : index, itemID: actions.materialID)) }
                }
                .tint(.accentColor)
            }
            .swipeActions(edge: .trailing) {
                Button("Note", systemImage: "note.text") { send(.note(index)) }
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

    @ViewBuilder
    private var tick: some View {
        if case let .selectingParagraphs(picked) = mode {
            Image(systemName: picked.contains(index) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(picked.contains(index) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .padding(10)
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

    private var paragraphNote: String {
        actions.annotations.first { $0.piece == index && $0.quote.isEmpty }?.note ?? ""
    }

    private var plainText: String {
        MarkedMarkdown.plainText(markdown, baseURL: baseURL)
    }

    private func saveNote(_ text: String) {
        Task { await library.apply(.note(text, actions.target(index, text: ""))) }
    }
}

/// A note in the margin: no background, a thin rule, top-aligned with its paragraph.
private struct MarginNote: View {
    let saved: String
    let editing: Bool
    let save: (String) -> Void
    let edit: () -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Capsule().fill(.tertiary).frame(width: 2)
            if editing {
                TextField("Note", text: $draft, axis: .vertical)
                    .focused($focused)
                    .onAppear { draft = saved; focused = true }
                    .onDisappear { if draft != saved { save(draft) } }
            } else {
                Text(saved).onTapGesture(perform: edit)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
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
