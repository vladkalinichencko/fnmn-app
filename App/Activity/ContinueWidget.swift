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

    private var shown: [WidgetItem] {
        let items = entry.snapshot.items
        let first = items.first ?? entry.snapshot.spare(at: entry.date)
        guard let first else {
            return []
        }
        return [first] + items.dropFirst().prefix(WidgetLayout.continueCount(for: family) - 1)
    }

    var body: some View {
        Group {
            if let head = shown.first {
                switch family {
                case .systemSmall:
                    ContinueHead(item: head, cover: nil)
                case .systemMedium:
                    ContinueHead(item: head, cover: 78)
                default:
                    VStack(alignment: .leading, spacing: 10) {
                        ContinueHead(item: head, cover: 92)
                        ForEach(shown.dropFirst()) { item in
                            ContinueLine(item: item)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                EmptyWidget(text: "Everything read", symbol: "checkmark.circle")
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

private struct ContinueHead: View {
    let item: WidgetItem
    let cover: CGFloat?

    var body: some View {
        Link(destination: item.deepLink) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    if let cover {
                        WidgetCover(item: item, side: cover)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Continue")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.title)
                            .font(cover == nil ? .subheadline.weight(.semibold) : .headline)
                            .lineLimit(cover == nil ? 4 : 3)
                            .minimumScaleFactor(0.85)
                        Text(item.source ?? item.kind.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                WidgetProgress(progress: item.progress)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ContinueLine: View {
    let item: WidgetItem

    var body: some View {
        Link(destination: item.deepLink) {
            HStack(spacing: 8) {
                WidgetProgress(progress: item.progress, height: 2)
                    .frame(width: 26)
                Text(item.title)
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct WidgetCover: View {
    let item: WidgetItem
    let side: CGFloat

    var body: some View {
        if let url = WidgetStore.cover(named: item.cover), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side * 0.78)
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
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
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
