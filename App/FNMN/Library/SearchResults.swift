import FNMNCore
import SwiftUI

struct SearchResults: View {
    let query: String
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @State private var state = SearchScreenState.idle

    var body: some View {
        let hits = state.hits
        List {
            ForEach(SearchSource.allCases, id: \.self) { source in
                let found = hits[source] ?? []
                if !found.isEmpty {
                    Section(source.title) {
                        ForEach(found) { hit in
                            Button {
                                open(hit)
                            } label: {
                                SearchRow(hit: hit, title: title(of: hit.itemID))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if state.isSearching {
                HStack {
                    ProgressView()
                        .progressViewStyle(GraySpinner())
                    Spacer(minLength: 0)
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if state.isReady, hits.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task(id: query) {
            await search()
        }
    }

    private func search() async {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            state = .idle
            return
        }
        state = .searching(needle, [])
        let found = await library.search(needle) { newHits in
            guard !Task.isCancelled, case let .searching(current, shown) = state, current == needle else {
                return
            }
            state = .searching(needle, shown + newHits)
        }
        guard !Task.isCancelled else {
            return
        }
        state = .ready(found)
    }

    private func title(of itemID: String) -> String {
        library.snapshot.articles.first { $0.material.id == itemID }?.material.title ?? itemID
    }

    private func open(_ hit: SearchHit) {
        switch hit.source {
        case .transcript:
            navigation.open(.item(hit.itemID, seconds: hit.seconds))
        case .material, .text, .annotation:
            navigation.open(.item(hit.itemID, piece: hit.piece))
        }
    }
}

private enum SearchScreenState: Equatable {
    case idle
    case searching(String, [SearchHit])
    case ready([SearchHit])

    var hits: [SearchSource: [SearchHit]] {
        switch self {
        case .idle:
            [:]
        case let .searching(_, found), let .ready(found):
            Dictionary(grouping: found, by: \.source)
        }
    }

    var isSearching: Bool {
        if case .searching = self {
            return true
        }
        return false
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

private struct SearchRow: View {
    let hit: SearchHit
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let seconds = hit.seconds {
                    Text(Self.time(seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !hit.text.isEmpty {
                Text(AttributedString.highlighted(hit.text, spans: [hit.span].compactMap(\.self)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private static func time(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
