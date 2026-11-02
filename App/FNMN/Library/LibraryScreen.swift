import FNMNCore
import SwiftUI

struct LibraryScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ImportJobs.self) private var imports
    @Environment(WindowNavigation.self) private var navigation
    @Environment(LibraryDialogs.self) private var dialogs
    @AppStorage("collectionGrouping") private var grouping = LibraryGrouping.albums
    @AppStorage("collectionSort") private var sort = GroupSort.standard
    @State private var query = ""

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.library) {
            let found = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : library.queries.items(matching: query)
            ScrollView {
                if let found {
                    ItemGrid(items: found).padding(.horizontal, Tokens.gutter)
                } else {
                    sections
                }
            }
            .background(Tokens.canvas)
            .noResults(for: query, when: found?.isEmpty == true)
            .screenSearch($query)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { dialogs.send(.openSettings) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Add", systemImage: "plus") {
                        Button("Link", systemImage: "link") { dialogs.send(.addLink("")) }
                        Button("File", systemImage: "doc") { dialogs.send(.pickFile) }
                        Button("New Collection", systemImage: "rectangle.stack.badge.plus") { dialogs.send(.nameAlbum(adding: nil)) }
                    }
                }
            }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: Tokens.sectionGap) {
            let continued = library.queries.continueItems(library.progress)
            if !continued.isEmpty {
                LibrarySection("Continue") { ItemGrid(items: continued) }
            }
            let preparing = imports.jobs.filter { $0.itemID == nil && !($0.readsLibraryFolder && $0.isPreparing) }
            let unsorted = library.queries.unsortedItems
            if !preparing.isEmpty || !unsorted.isEmpty {
                LibrarySection("Unsorted") {
                    LazyVGrid(columns: Tokens.grid, spacing: Tokens.gap) {
                        ForEach(preparing) { PreparingTile(job: $0) }
                        ForEach(unsorted) { ItemTile(item: $0) }
                    }
                }
            }
            LibrarySection("Collections") {
                CollectionOptions(grouping: $grouping, sort: $sort)
            } content: {
                LazyVGrid(columns: Tokens.grid, spacing: Tokens.gap) {
                    ForEach(library.queries.groups(by: grouping, sortedBy: sort, progress: library.progress)) { AlbumTile(album: $0) }
                }
            }
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.bottom, Tokens.sectionGap)
    }
}

/// A titled part of a screen with a large header, used by Library and Shelf.
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

/// What the Collections section gathers materials by, and in which order; the choice is kept.
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
