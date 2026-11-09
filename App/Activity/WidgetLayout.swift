import WidgetKit

enum WidgetLayout {
    static func continueCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall, .systemMedium: 1
        case .systemLarge: 3
        case .systemExtraLarge, .systemExtraLargePortrait: 7
        default: 1
        }
    }

    static func digestCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 2
        case .systemLarge: 4
        case .systemExtraLarge, .systemExtraLargePortrait: 6
        default: 1
        }
    }

    static func digestColumns(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium, .systemLarge: 2
        case .systemExtraLarge, .systemExtraLargePortrait: 3
        default: 1
        }
    }
}
