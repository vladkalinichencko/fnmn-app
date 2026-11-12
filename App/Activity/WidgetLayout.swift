import SwiftUI
import WidgetKit

enum WidgetLayout {
    static let spacing: CGFloat = 4
    static let gap: CGFloat = 8
    static let headerHeight: CGFloat = 16

    struct ContinuePlan: Equatable {
        var featured: Bool
        var rows: Int
        var columns: Int
        var itemCount: Int
    }

    static func continuePlan(for family: WidgetFamily) -> ContinuePlan {
        switch family {
        case .systemSmall:
            return ContinuePlan(featured: false, rows: 1, columns: 1, itemCount: 1)
        case .systemMedium:
            return ContinuePlan(featured: false, rows: 2, columns: 1, itemCount: 2)
        case .systemLarge:
            return ContinuePlan(featured: true, rows: 2, columns: 1, itemCount: 3)
        case .systemExtraLarge:
            return ContinuePlan(featured: true, rows: 4, columns: 2, itemCount: 7)
        case .systemExtraLargePortrait:
            return ContinuePlan(featured: true, rows: 5, columns: 1, itemCount: 6)
        default:
            return ContinuePlan(featured: false, rows: 1, columns: 1, itemCount: 1)
        }
    }

    static func digestColumns(for family: WidgetFamily) -> Int {
        switch family {
        case .systemExtraLarge:
            return 4
        case .systemSmall:
            return 1
        default:
            return 2
        }
    }

    static func digestRows(for family: WidgetFamily, postCount: Int) -> Int {
        let columns = digestColumns(for: family)
        guard postCount > 0 else {
            return 0
        }
        return min(Int(ceil(Double(postCount) / Double(columns))), maxDigestRows(for: family))
    }

    static func maxDigestRows(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall, .systemMedium:
            return 1
        case .systemLarge, .systemExtraLarge:
            return 2
        case .systemExtraLargePortrait:
            return 5
        default:
            return 1
        }
    }

}

struct ProgressLine: View {
    let progress: Double?
    var color: Color = .accentColor

    static let inset: CGFloat = 9
    static let thickness: CGFloat = 5
    static var clearance: CGFloat { inset + thickness + 6 }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let progress, progress > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(geometry.size.width * min(progress, 1), Self.thickness))
                }
            }
        }
        .frame(height: Self.thickness)
    }
}

extension View {
    func progressLine(_ progress: Double?, cornerRadius: CGFloat, color: Color = .accentColor) -> some View {
        overlay(alignment: .bottom) {
            if let progress, progress > 0 {
                ProgressLine(progress: progress, color: color)
                    .padding(.horizontal, cornerRadius)
                    .padding(.bottom, ProgressLine.inset)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct WidgetSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}


