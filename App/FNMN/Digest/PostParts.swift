import FNMNCore
import SwiftUI
import Textual

struct PostText: View {
    let text: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        StructuredText(text, parser: MarkedMarkdown(baseURL: nil, marks: [], width: nil))
            .plateText()
            .onChange(of: typeSize) { _, value in
                print("PostText typeSize → \(value)")
            }
    }
}

struct PostContextLabel: View {
    let kind: DigestPackage.Post.Context.Kind
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: PostCard.icon(kind))
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }
}

struct PostOpenButton: View {
    let url: URL
    let label: String
    var font: Font = .caption
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            Image(systemName: "arrow.up.right")
                .font(font)
                .padding(6)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}


