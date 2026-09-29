import FNMNCore
import SwiftUI

/// The search tab: titles, authors, sources, albums and section headings. Nothing shows until something is typed.
struct SearchScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.search) {
            let query = navigation.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let items = query.isEmpty ? [] : library.snapshot.items(matching: query)
            ScrollView {
                ItemGrid(items: items).padding(.horizontal, Tokens.gutter)
            }
            .background(Tokens.canvas)
            .overlay {
                if !query.isEmpty, items.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .navigationTitle("Search")
        }
    }
}
