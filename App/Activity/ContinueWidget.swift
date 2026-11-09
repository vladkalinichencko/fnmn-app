import SwiftUI
import WidgetKit

struct ContinueEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct ContinueProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueEntry {
        ContinueEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueEntry) -> Void) {
        completion(ContinueEntry(date: .now, snapshot: WidgetStore.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueEntry>) -> Void) {
        let entry = ContinueEntry(date: .now, snapshot: WidgetStore.read() ?? WidgetSnapshot())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(21_600))))
    }
}

struct ContinueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FNMNContinue", provider: ContinueProvider()) { entry in
            ContinueEntryView(entry: entry)
        }
        .configurationDisplayName("Continue")
        .description("Where reading stopped, and what waits next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .systemExtraLargePortrait])
    }
}

struct ContinueEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ContinueEntry

    private var items: [WidgetItem] {
        entry.snapshot.items
    }

    private var spare: WidgetItem? {
        entry.snapshot.spare(at: entry.date)
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                if let first = items.first ?? spare {
                    SmallItem(item: first)
                } else {
                    EmptyWidget(text: "Everything read", symbol: "checkmark.circle")
                }
            case .systemMedium:
                MiddleColumn(head: items.first ?? spare, rest: Array(items.dropFirst().prefix(2)))
            case .systemLarge:
                MiddleColumn(head: items.first ?? spare, rest: Array(items.dropFirst().prefix(4)))
            default:
                MiddleColumn(head: items.first ?? spare, rest: Array(items.dropFirst().prefix(7)))
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

private struct SmallItem: View {
    let item: WidgetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverLink(item: item, height: 74)
            Text("Continue")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            WidgetProgress(progress: item.progress)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(item.deepLink)
    }
}

private struct MiddleColumn: View {
    let head: WidgetItem?
    let rest: [WidgetItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let head {
                HeadItem(item: head)
            } else {
                EmptyWidget(text: "Everything read", symbol: "checkmark.circle")
            }
            ForEach(rest) { item in
                RestItem(item: item)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct HeadItem: View {
    let item: WidgetItem

    var body: some View {
        Link(destination: item.deepLink) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    CoverLink(item: item, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Continue")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(item.source ?? item.kind.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                WidgetProgress(progress: item.progress)
            }
        }
    }
}

private struct RestItem: View {
    let item: WidgetItem

    var body: some View {
        Link(destination: item.deepLink) {
            HStack(alignment: .center, spacing: 8) {
                WidgetProgress(progress: item.progress, height: 2)
                    .frame(width: 26)
                Text(item.title)
                    .font(.footnote)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct CoverLink: View {
    let item: WidgetItem
    let height: CGFloat

    var body: some View {
        if let url = WidgetStore.cover(named: item.cover), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: height * 1.3, height: height)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
        }
    }
}

struct WidgetProgress: View {
    let progress: Double
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.25))
                Capsule().fill(.primary)
                    .frame(width: max(geometry.size.width * min(max(progress, 0), 1), 0))
            }
        }
        .frame(height: height)
    }
}

struct EmptyWidget: View {
    let text: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

extension WidgetSnapshot {
    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            items: [
                WidgetItem(id: "article:one", title: "A Talk on Representation Learning", source: "Distill", progress: 0.42, piece: 12, cover: nil, kind: "article"),
                WidgetItem(id: "article:two", title: "Why Momentum Really Works", source: "Distill", progress: 0.18, piece: 4, cover: nil, kind: "article"),
                WidgetItem(id: "article:three", title: "Attention Is All You Need", source: "arXiv", progress: 0.66, piece: 30, cover: nil, kind: "article"),
            ],
            spares: [],
            digest: WidgetDigest(
                id: "digest", deliveredAt: .now,
                posts: [WidgetPost(id: "p1", text: "A model that reads its own output is not checking anything.", author: "Someone", network: "X")]
            )
        )
    }
}
