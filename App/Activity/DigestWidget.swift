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
        Group {
            if let digest = entry.digest, let first = digest.posts.first {
                switch family {
                case .systemSmall:
                    DigestHead(digest: digest, post: first)
                default:
                    DigestGrid(
                        digest: digest,
                        count: WidgetLayout.digestCount(for: family),
                        columns: WidgetLayout.digestColumns(for: family)
                    )
                }
            } else {
                EmptyWidget(text: "No digest yet", symbol: "newspaper")
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "fnmn://digest"))
    }
}

private struct DigestHead: View {
    let digest: WidgetDigest
    let post: WidgetPost

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DigestCaption(digest: digest, count: nil)
            Text(post.text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(5)
                .minimumScaleFactor(0.85)
            Text("\(post.author) · \(post.network)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DigestGrid: View {
    let digest: WidgetDigest
    let count: Int
    let columns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DigestCaption(digest: digest, count: digest.posts.count)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .topLeading), count: columns),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(digest.posts.prefix(count)) { post in
                    DigestCell(post: post)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DigestCaption: View {
    let digest: WidgetDigest
    let count: Int?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: digest.deliveredAt.hour < 12 ? "sunrise" : "sunset")
            Text(digest.deliveredAt.hour < 12 ? "Morning" : "Evening")
            Spacer(minLength: 0)
            if let count {
                Text(count, format: .number)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct DigestCell: View {
    let post: WidgetPost

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(post.text)
                .font(.caption)
                .lineLimit(4)
                .minimumScaleFactor(0.85)
            Text(post.author)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Date {
    var hour: Int {
        Calendar.current.component(.hour, from: self)
    }
}
