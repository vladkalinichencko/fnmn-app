import FNMNCore
import SwiftUI

/// The materials of an album, publisher, type or month, sorted and grouped as the reader chose for that screen;
/// the choice sits in the eye menu of the bar and is kept for each screen on its own.
struct ArrangedItems: View {
    let items: [LibraryItem]
    var album: String?
    @Environment(LibraryModel.self) private var library
    @AppStorage private var sort: ItemSort
    @AppStorage private var grouping: ItemGrouping

    init(items: [LibraryItem], album: String? = nil, scope: String) {
        self.items = items
        self.album = album
        _sort = AppStorage(wrappedValue: .newest, "itemSort.\(scope)")
        _grouping = AppStorage(wrappedValue: .none, "itemGrouping.\(scope)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.sectionGap) {
            let opened = sort == .opened ? library.progress.readings.compactMapValues(\.openedAt) : [:]
            ForEach(LibraryQueries.arrange(items, sortedBy: sort, groupedBy: grouping, opened: opened)) { section in
                VStack(alignment: .leading, spacing: Tokens.gap) {
                    if let title = section.title {
                        Text(title).font(.title2.weight(.black))
                    }
                    ItemGrid(items: section.items, album: album)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("View Options", systemImage: "eye") {
                    Section("Sort By") {
                        Picker("Sort By", selection: $sort) {
                            ForEach(ItemSort.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                    Section("Group By") {
                        Picker("Group By", selection: $grouping) {
                            ForEach(ItemGrouping.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
        }
    }
}

private extension ItemSort {
    var title: String {
        switch self {
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .title: "Title"
        case .opened: "Recently Opened"
        }
    }
}

private extension ItemGrouping {
    var title: String {
        switch self {
        case .none: "None"
        case .publishers: "Publisher"
        case .types: "Type"
        case .months: "Month Added"
        }
    }
}
