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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct PostAuthorLine<Trailing: View>: View {
    enum Size {
        case full, compact
    }

    let name: String
    let handle: String
    var size = Size.full
    let trailing: Trailing

    init(name: String, handle: String, size: Size = .full, @ViewBuilder trailing: () -> Trailing) {
        self.name = name
        self.handle = handle
        self.size = size
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name)
                .font(nameFont)
                .lineLimit(1)
            Text("@\(handle)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
    }

    private var nameFont: Font {
        switch size {
        case .full: .subheadline.weight(.semibold)
        case .compact: .footnote.weight(.semibold)
        }
    }
}
