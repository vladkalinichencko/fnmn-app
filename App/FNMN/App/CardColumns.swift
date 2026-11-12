import SwiftUI

struct CardColumns<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var idealWidth: CGFloat
    var spacing: CGFloat = Tokens.gap
    var height: (Item, CGFloat) -> Double = { _, _ in 1 }
    var limit: ((Int) -> Int)? = nil
    @ViewBuilder let content: (Item) -> Content

    @State private var width: CGFloat = 0

    var body: some View {
        let count = Self.columns(forWidth: width, idealWidth: idealWidth, spacing: spacing)
        let shown = Array(items.prefix(limit?(count) ?? items.count))
        let columnWidth = max((width - spacing * CGFloat(count - 1)) / CGFloat(count), 1)
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(Self.split(shown, into: count, columnWidth: columnWidth, height: height).enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: spacing) {
                    ForEach(column) { content($0) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .opacity(width > 0 ? 1 : 0)
    }

    static func columns(forWidth width: CGFloat, idealWidth: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int((width + spacing) / (idealWidth + spacing)))
    }

    static func split(_ items: [Item], into count: Int, columnWidth: CGFloat, height: (Item, CGFloat) -> Double) -> [[Item]] {
        var columns = Array(repeating: [Item](), count: max(count, 1))
        var heights = Array(repeating: 0.0, count: columns.count)
        for item in items {
            let shortest = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[shortest].append(item)
            heights[shortest] += height(item, columnWidth)
        }
        return columns
    }
}
