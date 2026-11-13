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

    func searchResults<Results: View>(
        query: Binding<String>,
        active: Bool = true,
        @ViewBuilder results: @escaping (String) -> Results
    ) -> some View {
        modifier(SearchResultsOverlay(query: query, active: active, results: results))
    }
}

private struct SearchResultsOverlay<Results: View>: ViewModifier {
    @Binding var query: String
    let active: Bool
    let results: (String) -> Results

    func body(content: Content) -> some View {
        ZStack {
            content
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if active, !needle.isEmpty {
                results(needle)
                    .background { Rectangle().fill(.thickMaterial).ignoresSafeArea() }
            }
        }
    }
}

struct SearchResultsList<Content: View>: View {
    let query: String
    let searching: Bool
    let empty: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        List {
            content()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if empty {
                if searching {
                    ProgressView()
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}
