import SwiftUI
import WidgetKit

enum WidgetLayout {
    static let spacing: CGFloat = 8

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
            return ContinuePlan(featured: true, rows: 2, columns: 4, itemCount: 7)
        case .systemExtraLargePortrait:
            return ContinuePlan(featured: true, rows: 5, columns: 1, itemCount: 6)
        @unknown default:
            return ContinuePlan(featured: false, rows: 1, columns: 1, itemCount: 1)
        }
    }

    static func coverSide(width: CGFloat, height: CGFloat) -> CGFloat {
        max(32, min(height - 24, width * 0.38))
    }

    static func digestColumns(for family: WidgetFamily) -> Int {
        switch family {
        case .systemExtraLarge:
            return 4
        case .systemSmall:
            return 1
        @unknown default:
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
        @unknown default:
            return 1
        }
    }
}

extension View {
    func widgetSurface() -> some View {
        padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ConcentricRectangle().fill(.quaternary)
            }
            .clipShape(ConcentricRectangle())
    }
}
