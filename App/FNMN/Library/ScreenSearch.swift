import FNMNCore
import SwiftUI

extension View {
    /// Pulling the screen down brings out a field that searches only what the screen holds: titles, authors,
    /// sources, collections and section headings, as `LibrarySnapshot.items(matching:among:)` reads them.
    func screenSearch(_ query: Binding<String>) -> some View {
        searchable(text: query, placement: .navigationBarDrawer(displayMode: .automatic))
    }

    /// The system's "No Results" over a screen whose search found nothing.
    func noResults(for query: String, when empty: Bool) -> some View {
        overlay {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty, empty { ContentUnavailableView.search(text: query) }
        }
    }
}
