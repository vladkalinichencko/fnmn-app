import FNMNCore
import SwiftUI

struct LibraryScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @Environment(LibraryDialogs.self) private var dialogs
    @AppStorage("collectionGrouping") private var grouping = LibraryGrouping.albums
    @AppStorage("collectionSort") private var sort = GroupSort.standard
    @State private var query = ""

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.library) {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView { sections }
                } else {
                    SearchResults(query: query)
                }
            }
            .background(Tokens.canvas)
            .screenSearch($query)
            .navigationTitle("Library")
            .appRefresh(title: "Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { dialogs.send(.openSettings(.library)) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Add", systemImage: "plus") {
                        Button("Link", systemImage: "link") { dialogs.send(.addLink("")) }
                        Button("File", systemImage: "doc") { dialogs.send(.pickFile) }
                        Button("New Collection", systemImage: "rectangle.stack.badge.plus") { dialogs.send(.nameAlbum(adding: nil)) }
                    }
                }
            }
        } destination: { route in
            RouteScreen(route: route)
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: Tokens.sectionGap) {
            let continued = library.queries.continueItems(library.progress)
            if !continued.isEmpty {
                LibrarySection("Continue") { ItemGrid(items: continued) }
            }
            UnsortedSection()
            LibrarySection("Collections") {
                CollectionOptions(grouping: $grouping, sort: $sort)
            } content: {
                CardColumns(items: library.queries.groups(by: grouping, sortedBy: sort, progress: library.progress), idealWidth: 170) { album in
                    AlbumTile(album: album)
                }
            }
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.bottom, Tokens.sectionGap)
    }
}

private struct UnsortedSection: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ImportJobs.self) private var imports

    var body: some View {
        let preparing = imports.jobs.filter { $0.itemID == nil && !($0.readsLibraryFolder && $0.isPreparing) }
        let unsorted = library.queries.unsortedItems
        if !preparing.isEmpty || !unsorted.isEmpty {
            LibrarySection("Unsorted") {
                CardColumns(items: UnsortedEntry.all(preparing: preparing, unsorted: unsorted), idealWidth: 170) { entry in
                    switch entry {
                    case let .job(job): PreparingTile(job: job)
                    case let .item(item): ItemTile(item: item)
                    }
                }
            }
        }
    }
}

private enum UnsortedEntry: Identifiable {
    case job(ImportJob)
    case item(LibraryItem)

    var id: String {
        switch self {
        case let .job(job): "job-\(job.id)"
        case let .item(item): "item-\(item.id)"
        }
    }

    static func all(preparing: [ImportJob], unsorted: [LibraryItem]) -> [UnsortedEntry] {
        preparing.map(UnsortedEntry.job) + unsorted.map(UnsortedEntry.item)
    }
}

struct LibrarySection<Content: View, Accessory: View>: View {
    let title: String
    let accessory: Accessory
    let content: Content

    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.gap) {
            HStack {
                Text(title).font(Tokens.sectionTitle)
                Spacer(minLength: 4)
                accessory
            }
            content
        }
    }
}

extension LibrarySection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
    }
}

private struct CollectionOptions: View {
    @Binding var grouping: LibraryGrouping
    @Binding var sort: GroupSort

    var body: some View {
        Menu {
            Section("Group By") {
                Picker("Group By", selection: $grouping) {
                    ForEach(LibraryGrouping.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
            Section("Sort By") {
                Picker("Sort By", selection: $sort) {
                    ForEach(GroupSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Image(systemName: "eye")
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 31, height: 31)
        }
        .accessibilityLabel("View Options")
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}

private extension LibraryGrouping {
    var title: String {
        switch self {
        case .albums: "My Collections"
        case .publishers: "Publishers"
        case .types: "Types"
        case .months: "Month Added"
        }
    }
}

private extension GroupSort {
    var title: String {
        switch self {
        case .standard: "Default"
        case .name: "Name"
        case .size: "Most Items"
        case .recent: "Recently Added"
        case .opened: "Recently Opened"
        }
    }
}
