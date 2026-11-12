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

    private func stream(count: Int) -> (items: [WidgetItem], othersStart: Int?) {
        let snapshot = entry.snapshot
        let items = Array(snapshot.items.prefix(count))
        var known = Set(items.map(\.id))
        var others: [WidgetItem] = []
        if items.isEmpty, let spare = snapshot.spare(at: entry.date) {
            others.append(spare)
            known.insert(spare.id)
        }
        let remaining = count - items.count - others.count
        if remaining > 0 {
            for spare in snapshot.spares(from: entry.date, count: remaining) where known.insert(spare.id).inserted {
                others.append(spare)
            }
        }
        return (items + others, others.isEmpty ? nil : items.count)
    }

    var body: some View {
        GeometryReader { geometry in
            let plan = WidgetLayout.continuePlan(for: family)
            let stream = stream(count: plan.itemCount)
            ContinueContent(items: stream.items, othersStart: stream.othersStart, plan: plan, size: geometry.size)
        }
        .containerBackground(.background, for: .widget)
    }
}

private struct ContinueContent: View {
    let items: [WidgetItem]
    let othersStart: Int?
    let plan: WidgetLayout.ContinuePlan
    let size: CGSize

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyWidget(text: "Everything read", symbol: "checkmark.circle")
            } else if plan.columns > 1 {
                ContinueColumns(items: items, othersStart: othersStart, size: size)
            } else {
                ContinueColumn(items: items, othersStart: othersStart, plan: plan, size: size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum ContinueCell {
    case item(Int)
    case header(String)
}

private func sectionTitle(othersStart: Int?) -> String {
    othersStart == 0 ? "Other" : "Continue"
}

private func continueCells(items: [WidgetItem], othersStart: Int?, in range: Range<Int>) -> [ContinueCell] {
    var cells: [ContinueCell] = []
    for index in range where index < items.count {
        if let othersStart, othersStart > 0, index == othersStart {
            cells.append(.header("Other"))
        }
        cells.append(.item(index))
    }
    return cells
}

private struct ContinueColumn: View {
    let items: [WidgetItem]
    let othersStart: Int?
    let plan: WidgetLayout.ContinuePlan
    let size: CGSize

    private var cells: [ContinueCell] {
        continueCells(items: items, othersStart: othersStart, in: 0 ..< items.count)
    }

    private var headerCount: Int {
        cells.count - items.count + 1
    }

    private var featured: Bool {
        plan.featured && !items.isEmpty
    }

    private var rowUnits: Int {
        items.count - (featured ? 1 : 0)
    }

    private var unit: CGFloat {
        guard featured, rowUnits > 0 else {
            return 0
        }
        let chrome = CGFloat(headerCount) * (WidgetLayout.headerHeight + WidgetLayout.gap)
        return (size.height - chrome - WidgetLayout.gap * CGFloat(rowUnits + 1)) / CGFloat(rowUnits + 2)
    }

    private var featuredHeight: CGFloat {
        guard featured else {
            return 0
        }
        if rowUnits == 0 {
            return size.height - CGFloat(headerCount) * (WidgetLayout.headerHeight + WidgetLayout.gap)
        }
        return unit * 2 + WidgetLayout.gap
    }

    var body: some View {
        VStack(spacing: WidgetLayout.gap) {
            WidgetSectionHeader(title: sectionTitle(othersStart: othersStart))
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                switch cell {
                case .header(let title):
                    WidgetSectionHeader(title: title)
                case .item(let index):
                    let cell = ItemCell(
                        item: items[index],
                        prominent: (featured && index == 0) || plan.rows == 1,
                        adaptive: plan.rows != 1
                    )
                    if featured && index == 0 {
                        cell.frame(width: size.width, height: featuredHeight)
                    } else if featured {
                        cell.frame(height: unit)
                    } else {
                        cell
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

private struct ContinueColumns: View {
    let items: [WidgetItem]
    let othersStart: Int?
    let size: CGSize

    private var columnWidth: CGFloat {
        (size.width - WidgetLayout.gap) / 2
    }

    var body: some View {
        HStack(alignment: .top, spacing: WidgetLayout.gap) {
            column(range: 0 ..< 3, title: sectionTitle(othersStart: othersStart))
            column(range: 3 ..< 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func column(range: Range<Int>, title: String? = nil) -> some View {
        var cells = continueCells(items: items, othersStart: othersStart, in: range)
        if let title {
            cells.insert(.header(title), at: 0)
        }
        var headers = 0
        var units = 0
        var featured = false
        for cell in cells {
            switch cell {
            case .header:
                headers += 1
            case .item(let index):
                units += index == 0 ? 2 : 1
                featured = featured || index == 0
            }
        }
        let chrome = CGFloat(headers) * WidgetLayout.headerHeight
            + WidgetLayout.gap * CGFloat(max(cells.count - 1, 0))
            + (featured ? WidgetLayout.gap : 0)
        let unit = (size.height - chrome) / CGFloat(max(units, 1))
        return VStack(spacing: WidgetLayout.gap) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                switch cell {
                case .header(let title):
                    WidgetSectionHeader(title: title)
                case .item(let index):
                    let cell = ItemCell(item: items[index], prominent: index == 0)
                    if index == 0 {
                        cell.frame(width: columnWidth, height: unit * 2 + WidgetLayout.gap)
                    } else {
                        cell.frame(height: unit)
                    }
                }
            }
        }
        .frame(width: columnWidth, alignment: .top)
    }
}

private struct ItemCell: View {
    let item: WidgetItem
    var prominent: Bool = false
    var adaptive: Bool = true

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var showsCover: Bool {
        renderingMode == .fullColor && WidgetStore.cover(named: item.cover) != nil
    }

    private var titleFont: Font {
        prominent ? .callout.weight(.semibold) : .footnote.weight(.semibold)
    }

    var body: some View {
        Link(destination: item.deepLink) { face }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var face: some View {
        GeometryReader { geometry in
            Group {
                if showsCover {
                    HStack(spacing: WidgetLayout.spacing) {
                        WidgetCover(name: item.cover, width: min(geometry.size.width * 0.4, geometry.size.height))
                        label
                    }
                } else {
                    label
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var label: some View {
        Group {
            if adaptive {
                adaptiveContent
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(titleFont)
                        .lineLimit(prominent ? 6 : 2)
                    Spacer(minLength: 0)
                    meta
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetAccentable()
    }

    private static let metaHeight: CGFloat = 18

    private var adaptiveContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .vertical) {
                title(lines: 6)
                title(lines: 4)
                title(lines: 3)
                title(lines: 2)
                title(lines: 1)
            }
            .padding(.bottom, Self.metaHeight)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottomLeading) {
            meta
        }
    }

    private func title(lines: Int) -> some View {
        Text(item.title)
            .font(titleFont)
            .lineLimit(lines)
    }

    private var meta: some View {
        HStack(spacing: 6) {
            Text(item.source ?? item.kind.capitalized)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if item.progress > 0 {
                ProgressLine(progress: item.progress)
                    .frame(minWidth: 12, maxWidth: 72)
            }
        }
    }
}

private struct WidgetCover: View {
    let name: String?
    let width: CGFloat

    var body: some View {
        if let url = WidgetStore.cover(named: name) {
            Color.clear
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(Color.secondary.opacity(0.12))
                .overlay {
                    FileImage(url: url, contentMode: .fill)
                }
                .clipShape(.rect(cornerRadius: WidgetLayout.spacing))
        }
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
        .widgetAccentable()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}


