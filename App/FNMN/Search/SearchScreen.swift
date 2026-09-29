import FNMNCore
import SwiftUI

/// The search tab: titles, authors, sources, albums and section headings. An empty field shows recent materials.
struct SearchScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.search) {
            let query = navigation.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let items = query.isEmpty ? Array(library.snapshot.items.prefix(12)) : library.snapshot.items(matching: query)
            ScrollView {
                ItemGrid(items: items).padding(.horizontal, Tokens.gutter)
            }
            .background(Tokens.canvas)
            .overlay {
                if items.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .navigationTitle("Search")
        }
    }
}
