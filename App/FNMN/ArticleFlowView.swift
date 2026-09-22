import AVKit
import SwiftUI

struct ArticleFlowView: View {
    @Environment(LibraryModel.self) private var library
    let package: ImportPackage

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(ArticleBody.pieces(in: package.body ?? "").enumerated()), id: \.offset) { _, piece in
                    pieceView(piece)
                }
            }
            .padding()
        }
        .navigationTitle(package.material.title)
        .toolbar {
            Link("Source", destination: package.material.sourceURL)
        }
    }

    @ViewBuilder
    private func pieceView(_ piece: ArticlePiece) -> some View {
        switch piece {
        case let .text(source):
            markdown(source)
        case let .image(alt, path):
            if let file = LibraryFile.articleFile(root: library.storageURL, materialID: package.material.id, path: path),
               let image = UIImage(contentsOfFile: file.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(alt.isEmpty ? path : alt)
            }
        case let .video(path):
            if let file = LibraryFile.articleFile(root: library.storageURL, materialID: package.material.id, path: path) {
                ArticleVideo(url: file)
            } else {
                Text(path)
            }
        case let .interactive(url, selector):
            LiveCropView(url: url, selector: selector)
        }
    }

    private func markdown(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let attributed = try? AttributedString(markdown: source, options: options) {
            return Text(attributed)
        }
        return Text(source)
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
