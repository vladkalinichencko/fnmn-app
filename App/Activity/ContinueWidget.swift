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

    private func shown(count: Int) -> [WidgetItem] {
        let snapshot = entry.snapshot
        var shown = Array(snapshot.items.prefix(count))
        if shown.isEmpty, let spare = snapshot.spare(at: entry.date) {
            shown = [spare]
        }
        if shown.count < count {
            let known = Set(shown.map(\.id))
            let fill = snapshot.spares(from: entry.date, count: count - shown.count).filter { !known.contains($0.id) }
            shown.append(contentsOf: fill)
        }
        return shown
    }

    var body: some View {
        GeometryReader { geometry in
            let plan = WidgetLayout.continuePlan(for: family)
            ContinueContent(items: shown(count: plan.itemCount), plan: plan, size: geometry.size)
        }
        .containerBackground(.background, for: .widget)
    }
}

private struct ContinueContent: View {
    let items: [WidgetItem]
    let plan: WidgetLayout.ContinuePlan
    let size: CGSize

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyWidget(text: "Everything read", symbol: "checkmark.circle")
            } else if plan.columns > 1, items.count >= plan.itemCount {
                ContinueMosaic(items: items, columns: plan.columns, size: size)
            } else {
                ContinueColumn(items: items, plan: plan, size: size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ContinueColumn: View {
    let items: [WidgetItem]
    let plan: WidgetLayout.ContinuePlan
    let size: CGSize

    var body: some View {
        Group {
            if let head = items.first {
                if plan.featured {
                    let rowCount = max(0, min(plan.rows, items.count - 1))
                    if rowCount == 0 {
                        ContinueFeature(item: head, width: size.width, height: size.height)
                    } else {
                        let unit = (size.height - WidgetLayout.spacing * CGFloat(rowCount + 1)) / CGFloat(rowCount + 2)
                        let featuredHeight = unit * 2 + WidgetLayout.spacing
                        VStack(spacing: WidgetLayout.spacing) {
                            ContinueFeature(item: head, width: size.width, height: featuredHeight)
                            ForEach(Array(items.dropFirst().prefix(rowCount))) { item in
                                ContinueRow(item: item, coverSide: WidgetLayout.coverSide(width: size.width, height: unit))
                                    .frame(height: unit)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                    }
                } else {
                    let rowCount = max(1, min(plan.rows, items.count))
                    let rowHeight = (size.height - WidgetLayout.spacing * CGFloat(rowCount - 1)) / CGFloat(rowCount)
                    VStack(spacing: WidgetLayout.spacing) {
                        ForEach(Array(items.prefix(rowCount))) { item in
                            ContinueRow(
                                item: item,
                                coverSide: WidgetLayout.coverSide(width: size.width, height: rowHeight),
                                lines: rowHeight > 120 ? 4 : 2
                            )
                            .frame(height: rowHeight)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                }
            } else {
                EmptyWidget(text: "Everything read", symbol: "checkmark.circle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ContinueMosaic: View {
    let items: [WidgetItem]
    let columns: Int
    let size: CGSize

    var body: some View {
        Group {
            if let head = items.first {
                let columnWidth = (size.width - WidgetLayout.spacing * CGFloat(columns - 1)) / CGFloat(columns)
                let rowHeight = (size.height - WidgetLayout.spacing) / 2
                let featuredWidth = columnWidth * 2 + WidgetLayout.spacing
                let rest = Array(items.dropFirst().prefix(columns * 2 - 2))
                VStack(spacing: WidgetLayout.spacing) {
                    HStack(spacing: WidgetLayout.spacing) {
                        ContinueFeature(item: head, width: featuredWidth, height: rowHeight)
                        ForEach(rest.prefix(columns - 2)) { item in
                            ContinueRow(
                                item: item,
                                coverSide: WidgetLayout.coverSide(width: columnWidth, height: rowHeight)
                            )
                            .frame(width: columnWidth, height: rowHeight)
                        }
                    }
                    HStack(spacing: WidgetLayout.spacing) {
                        ForEach(rest.dropFirst(columns - 2).prefix(columns)) { item in
                            ContinueRow(
                                item: item,
                                coverSide: WidgetLayout.coverSide(width: columnWidth, height: rowHeight)
                            )
                            .frame(width: columnWidth, height: rowHeight)
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
            } else {
                EmptyWidget(text: "Everything read", symbol: "checkmark.circle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ContinueFeature: View {
    let item: WidgetItem
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Link(destination: item.deepLink) {
            HStack(spacing: WidgetLayout.spacing) {
                WidgetCover(item: item, side: WidgetLayout.coverSide(width: width, height: height))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                    Text(item.source ?? item.kind.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .widgetSurface()
        .frame(width: width, height: height)
    }
}

private struct ContinueRow: View {
    let item: WidgetItem
    let coverSide: CGFloat
    var lines: Int = 2

    var body: some View {
        Link(destination: item.deepLink) {
            HStack(spacing: WidgetLayout.spacing) {
                WidgetCover(item: item, side: coverSide)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(lines)
                        .minimumScaleFactor(0.85)
                    Text(item.source ?? item.kind.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .widgetSurface()
    }
}

private struct WidgetCover: View {
    let item: WidgetItem
    let side: CGFloat

    var body: some View {
        Color.clear
            .frame(width: side, height: side)
            .background {
                if let url = WidgetStore.cover(named: item.cover), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.12)
                        .overlay {
                            Image(systemName: item.symbol)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .clipShape(.rect(cornerRadius: WidgetLayout.spacing))
            .overlay(alignment: .bottom) {
                if item.progress > 0 {
                    WidgetProgress(progress: item.progress, height: 4)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
            }
    }
}

struct WidgetProgress: View {
    let progress: Double
    var height: CGFloat = 5

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
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private extension WidgetItem {
    var symbol: String {
        switch kind {
        case "video":
            return "play.rectangle.fill"
        case "book":
            return "book.closed"
        case "link":
            return "link"
        default:
            return "doc.text"
        }
    }
}
