import FNMNCore
import SwiftUI

struct SearchResults: View {
    let query: String
    var corpus: Set<String>?
    var groups: @MainActor ([SearchHit]) -> [(title: String, hits: [SearchHit])] = SearchResults.bySource
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @State private var state = SearchScreenState.idle

    var body: some View {
        let found = state.all.filter { corpus?.contains($0.itemID) ?? true }
        let sections = groups(found)
        SearchResultsList(query: query, searching: state.isSearching, empty: sections.allSatisfy(\.hits.isEmpty)) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                Section(section.title) {
                    ForEach(section.hits) { hit in
                        Button {
                            navigation.open(hit.route)
                        } label: {
                            ResultRow(title: library.queries.item(hit.itemID)?.title ?? hit.itemID, excerpt: hit.text, spans: [hit.span].compactMap(\.self), seconds: hit.seconds)
                        }
                        .buttonStyle(.plain)
                    }
                }
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
            guard !Task.isCancelled else {
                return
            }
            state.absorb(newHits, needle: needle)
        }
        guard !Task.isCancelled else {
            return
        }
        state = .ready(found)
    }

    static func bySource(_ hits: [SearchHit]) -> [(title: String, hits: [SearchHit])] {
        let grouped = Dictionary(grouping: hits, by: \.source)
        return SearchSource.allCases.compactMap { source in
            let found = grouped[source] ?? []
            return found.isEmpty ? nil : (source.title, found)
        }
    }
}

extension SearchHit {
    var route: Route {
        switch source {
        case .transcript:
            .item(itemID, seconds: seconds)
        case .material, .text, .annotation:
            .item(itemID, piece: piece)
        }
    }
}

enum SearchScreenState: Equatable {
    case idle
    case searching(String, [SearchHit])
    case ready([SearchHit])

    var all: [SearchHit] {
        switch self {
        case .idle:
            []
        case let .searching(_, found), let .ready(found):
            found
        }
    }

    var isSearching: Bool {
        if case .searching = self {
            return true
        }
        return false
    }

    mutating func absorb(_ newHits: [SearchHit], needle: String) {
        guard case let .searching(current, shown) = self, current == needle else {
            return
        }
        self = .searching(current, shown + newHits)
    }
}

struct ResultRow: View {
    let title: String
    var subtitle: String?
    var excerpt: String?
    var spans: [TextSpan] = []
    var seconds: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let seconds {
                    Text(Self.time(seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let excerpt, !excerpt.isEmpty {
                Text(AttributedString.highlighted(excerpt, spans: spans))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    static func time(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
