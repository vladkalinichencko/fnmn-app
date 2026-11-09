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
                    DigestHead(digest: digest, post: first, lines: 5)
                case .systemMedium:
                    VStack(alignment: .leading, spacing: 8) {
                        DigestHead(digest: digest, post: first, lines: 3)
                        ForEach(digest.posts.dropFirst().prefix(1)) { post in
                            DigestLine(post: post)
                        }
                        Spacer(minLength: 0)
                    }
                case .systemLarge:
                    DigestColumn(digest: digest, count: 4)
                default:
                    DigestColumn(digest: digest, count: 6)
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
    let lines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: digest.deliveredAt.hour < 12 ? "sunrise" : "sunset")
                Text(digest.deliveredAt.hour < 12 ? "Morning" : "Evening")
                Spacer(minLength: 0)
                Text(digest.deliveredAt, format: .dateTime.hour().minute())
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            Text(post.text)
                .font(.headline)
                .lineLimit(lines)
            Text("\(post.author) · \(post.network)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DigestColumn: View {
    let digest: WidgetDigest
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: digest.deliveredAt.hour < 12 ? "sunrise" : "sunset")
                Text(digest.deliveredAt.hour < 12 ? "Morning Digest" : "Evening Digest")
                Spacer(minLength: 0)
                Text(digest.posts.count, format: .number)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(digest.posts.prefix(count)) { post in
                DigestLine(post: post)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DigestLine: View {
    let post: WidgetPost

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(post.text)
                .font(.footnote)
                .lineLimit(2)
            Text("\(post.author) · \(post.network)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private extension Date {
    var hour: Int {
        Calendar.current.component(.hour, from: self)
    }
}
