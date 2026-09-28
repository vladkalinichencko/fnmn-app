import AVKit
import SwiftMath
import SwiftUI
import UIKit

struct DocumentColumn: View {
    let pieces: [ArticlePiece]
    let visible: [Int]
    let file: (String) -> URL?
    let marks: (Int) -> [ParagraphQuoteMark]
    let tint: Int?
    let selection: Set<Int>
    @Binding var scrollID: Int?
    let onSelect: (Int) -> Void
    let onTap: (Int) -> Void
    let onNote: (Int) -> Void
    let onQuote: (Int, String) -> Void

    var body: some View {
        List {
            ForEach(visible, id: \.self) { index in
                pieceView(pieces[index], index: index)
                    .id(index)
                    .listRowBackground(rowBackground(index))
                    .contentShape(Rectangle())
                    .onLongPressGesture { onSelect(index) }
                    .onTapGesture { onTap(index) }
                    .swipeActions(edge: .trailing) {
                        Button("Note") { onNote(index) }
                    }
            }
        }
        .scrollPosition(id: $scrollID, anchor: .top)
    }

    @ViewBuilder
    private func pieceView(_ piece: ArticlePiece, index: Int) -> some View {
        let marks = marks(index)
        switch piece {
        case let .paragraph(runs):
            if let heading = ArticleBody.heading(runs), let body = ArticleBody.headingBody(runs) {
                markedText(paragraphAttributed(body), marks: marks)
                    .font(headingFont(heading.level))
            } else if let lines = plainLines(runs) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        markedPlain(line.isEmpty ? " " : line, marks: marks)
                    }
                }
            } else if runs.count == 1, case let .text(source) = runs[0] {
                SelectableParagraph(text: source, marks: marks, onSelectParagraph: { onSelect(index) }) { quote in
                    onQuote(index, quote)
                }
            } else {
                markedText(paragraphAttributed(runs), marks: marks)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .displayMath(latex):
            if parses(latex) {
                ScrollView(.horizontal) {
                    MathLabel(latex: latex)
                }
                .scrollIndicators(.hidden)
            } else {
                markedPlain(latex, marks: marks)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .image(alt, path):
            if let file = file(path), let image = UIImage(contentsOfFile: file.path) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Text(alt.isEmpty ? path : alt)
            }
        case let .video(path):
            if let file = file(path) {
                ArticleVideo(url: file)
            } else {
                Text(path)
            }
        case let .interactive(url, selector):
            LiveCropView(url: url, selector: selector)
        }
    }

    private func rowBackground(_ index: Int) -> Color? {
        if selection.contains(index) { return Color.accentColor.opacity(0.18) }
        if index == tint { return Color.accentColor.opacity(0.08) }
        return nil
    }

    private func markedPlain(_ text: String, marks: [ParagraphQuoteMark]) -> Text {
        markedText(AttributedString(text), marks: marks)
    }

    private func markedText(_ base: AttributedString, marks: [ParagraphQuoteMark]) -> Text {
        guard !marks.isEmpty else { return Text(base) }
        let mutable = NSMutableAttributedString(attributedString: NSAttributedString(base))
        applyQuoteMarks(mutable, marks: marks)
        return Text(AttributedString(mutable))
    }

    private func plainLines(_ runs: [ArticleRun]) -> [String]? {
        guard runs.count == 1, case let .text(source) = runs[0], source.contains("\n") else { return nil }
        return source.components(separatedBy: "\n")
    }

    private func parses(_ latex: String) -> Bool {
        var error: NSError?
        return MTMathListBuilder.build(fromString: latex, error: &error) != nil && error == nil
    }

    private func paragraphAttributed(_ runs: [ArticleRun]) -> AttributedString {
        var attributed = AttributedString()
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        for run in runs {
            switch run {
            case let .text(source):
                attributed += (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
            case let .math(latex):
                attributed += inlineMath(latex)
            }
        }
        return attributed
    }

    private func inlineMath(_ latex: String) -> AttributedString {
        let rendered = MTMathImage(latex: latex, fontSize: 17, textColor: .label, labelMode: .text, textAlignment: .left)
        let (error, picture) = rendered.asImage()
        guard error == nil, let picture else { return AttributedString(latex) }
        let attachment = NSTextAttachment()
        attachment.image = picture
        return AttributedString(NSAttributedString(attachment: attachment))
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title
        case 2: .title2
        default: .title3
        }
    }
}

private struct MathLabel: UIViewRepresentable {
    let latex: String

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.displayErrorInline = false
        label.textAlignment = .left
        label.labelMode = .display
        label.fontSize = 22
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: MTMathUILabel, context: Context) {
        label.latex = latex
        label.textColor = .label
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        let size = uiView.intrinsicContentSize
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }
}

private struct ArticleVideo: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .frame(height: 220)
            .task { player = AVPlayer(url: url) }
    }
}
