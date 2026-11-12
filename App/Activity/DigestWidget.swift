import SwiftUI
import WidgetKit

struct DigestEntry: TimelineEntry {
    let date: Date
    let digest: WidgetDigest?
}

struct DigestProvider: TimelineProvider {
    func placeholder(in context: Context) -> DigestEntry {
        DigestEntry(date: .now, digest: WidgetSnapshot.placeholder.digest)
    }

    func getSnapshot(in context: Context, completion: @escaping (DigestEntry) -> Void) {
        completion(DigestEntry(date: .now, digest: WidgetStore.read()?.digest ?? WidgetSnapshot.placeholder.digest))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DigestEntry>) -> Void) {
        let entry = DigestEntry(date: .now, digest: WidgetStore.read()?.digest)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(10_800))))
    }
}

struct DigestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FNMNDigest", provider: DigestProvider()) { entry in
            DigestEntryView(entry: entry)
        }
        .configurationDisplayName("Digest")
        .description("The latest digest the Mac built, morning or evening.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .systemExtraLargePortrait])
    }
}

struct DigestEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DigestEntry

    var body: some View {
        GeometryReader { geometry in
            DigestContent(digest: entry.digest, family: family, size: geometry.size)
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "fnmn://digest"))
    }
}

private struct DigestContent: View {
    let digest: WidgetDigest?
    let family: WidgetFamily
    let size: CGSize

    var body: some View {
        Group {
            if let digest, !digest.posts.isEmpty {
                DigestGrid(digest: digest, family: family, size: size)
            } else {
                EmptyWidget(text: "No digest yet", symbol: "newspaper")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DigestGrid: View {
    let digest: WidgetDigest
    let family: WidgetFamily
    let size: CGSize

    private var columns: Int {
        WidgetLayout.digestColumns(for: family)
    }

    private var rows: Int {
        WidgetLayout.digestRows(for: family, postCount: digest.posts.count)
    }

    private var posts: [WidgetPost] {
        Array(digest.posts.prefix(columns * rows))
    }

    private var rowPosts: [[WidgetPost]] {
        stride(from: 0, to: posts.count, by: columns).map { start in
            Array(posts[start..<min(start + columns, posts.count)])
        }
    }

    var body: some View {
        Group {
            if posts.isEmpty {
                EmptyWidget(text: "No digest yet", symbol: "newspaper")
            } else {
                let rowHeight = (size.height - WidgetLayout.spacing * CGFloat(max(0, rows - 1))) / CGFloat(max(1, rows))
                VStack(spacing: WidgetLayout.spacing) {
                    ForEach(rowPosts.indices, id: \.self) { index in
                        HStack(spacing: WidgetLayout.spacing) {
                            ForEach(rowPosts[index]) { post in
                                DigestCell(post: post, large: columns == 1 && rows == 1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DigestCell: View {
    let post: WidgetPost
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(post.text)
                .font(large ? .callout.weight(.medium) : .caption)
                .lineLimit(large ? 8 : 5)
            Spacer(minLength: 0)
            Text("\(post.author) · \(post.network)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetSurface()
    }
}
