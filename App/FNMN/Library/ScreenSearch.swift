import FNMNCore
import SwiftUI

extension View {
    func screenSearch(_ query: Binding<String>) -> some View {
        searchable(text: query, placement: .navigationBarDrawer(displayMode: .automatic))
    }

    func noResults(for query: String, when empty: Bool) -> some View {
        overlay {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty, empty { ContentUnavailableView.search(text: query) }
        }
    }
}
