import AVKit
import SwiftMath
import SwiftUI
import UIKit

struct DocumentColumn: View {
    let markdown: String
    let file: (String) -> URL?
    let piece: Int?
    var highlights: [Highlight] = []
    var onVisiblePiece: (Int, Int) -> Void = { _, _ in }
    var onHighlight: (Int, String) -> Void = { _, _ in }
    @State private var pinned: Int?

    var body: some View {
        let pieces = ArticleBody.pieces(in: markdown)
        List {
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, item in
                pieceView(item, index: index)
                    .id(index)
            }
        }
        .scrollPosition(id: $pinned, anchor: .top)
        .onChange(of: piece, initial: true) { _, piece in
            guard let piece else { return }
            pinned = piece
        }
        .onChange(of: pinned) { _, index in
            guard let index, pieces.indices.contains(index) else { return }
            onVisiblePiece(index, pieces.count)
        }
    }

    @ViewBuilder
    private func pieceView(_ piece: ArticlePiece, index: Int) -> some View {
        switch piece {
        case let .paragraph(runs):
            if let heading = ArticleBody.heading(runs), let body = ArticleBody.headingBody(runs) {
                paragraphText(body).font(headingFont(heading.level))
            } else if let lines = plainLines(runs) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                    }
                }
            } else if runs.count == 1, case let .text(source) = runs[0] {
                SelectableParagraph(text: source, quotes: highlights.filter { $0.piece == index }.map(\.quote)) { quote in
                    onHighlight(index, quote)
                }
            } else {
                paragraphText(runs).frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .displayMath(latex):
            if parses(latex) {
                ScrollView(.horizontal) {
                    MathLabel(latex: latex, mode: .display)
                }
                .scrollIndicators(.hidden)
            } else {
                Text(latex).frame(maxWidth: .infinity, alignment: .leading)
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

    private func plainLines(_ runs: [ArticleRun]) -> [String]? {
        guard runs.count == 1, case let .text(source) = runs[0], source.contains("\n") else { return nil }
        return source.components(separatedBy: "\n")
    }

    private func parses(_ latex: String) -> Bool {
        var error: NSError?
        return MTMathListBuilder.build(fromString: latex, error: &error) != nil && error == nil
    }

    private func paragraphText(_ runs: [ArticleRun]) -> Text {
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
        return Text(attributed)
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
    let mode: MTMathUILabelMode

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.displayErrorInline = false
        label.textAlignment = .left
        label.labelMode = mode
        label.fontSize = mode == .display ? 22 : 17
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: MTMathUILabel, context: Context) {
        label.latex = latex
        label.textColor = .label
        label.labelMode = mode
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
