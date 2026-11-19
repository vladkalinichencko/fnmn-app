import Foundation
import os

public struct SearchIndex: Sendable {
    private struct Entry: Sendable {
        let body: SearchBody
        let foldedParagraphs: [Int: String]
        let foldedCues: [Int: String]
    }

    private let bodies: [String: SearchBody]
    private let plainText: @Sendable (String) -> String
    private let cache = OSAllocatedUnfairLock(initialState: [String: Entry]())

    private init(bodies: [String: SearchBody], plainText: @escaping @Sendable (String) -> String) {
        self.bodies = bodies
        self.plainText = plainText
    }

    public static func load(bodies: [String: SearchBody], plainText: @escaping @Sendable (String) -> String) async -> SearchIndex {
        SearchIndex(bodies: bodies, plainText: plainText)
    }

    private func makeEntry(_ raw: SearchBody) -> Entry {
        let body = SearchBody(
            materialID: raw.materialID,
            paragraphs: raw.paragraphs.map { SearchParagraph(piece: $0.piece, markdown: plainText($0.markdown)) },
            cues: raw.cues.map { SearchCue(seconds: $0.seconds, text: plainText($0.text)) }
        )
        return Entry(
            body: body,
            foldedParagraphs: Dictionary(uniqueKeysWithValues: body.paragraphs.map { ($0.piece, TextFold.folded($0.markdown)) }),
            foldedCues: Dictionary(uniqueKeysWithValues: body.cues.enumerated().map { ($0.offset, TextFold.folded($0.element.text)) })
        )
    }

    private func entry(for materialID: String) -> Entry? {
        if let cached = cache.withLock({ $0[materialID] }) {
            return cached
        }
        guard !Task.isCancelled, let raw = bodies[materialID] else {
            return nil
        }
        let made = makeEntry(raw)
        cache.withLock { $0[materialID] = made }
        return made
    }

    public func hits(
        query: String,
        articles: [ArticleEntry],
        annotations: [Annotation],
        addedAt: [String: Date],
        yield: @MainActor ([SearchHit]) -> Void = { _ in }
    ) async -> [SearchHit] {
        let needle = query
        guard needle.contains(where: { !$0.isWhitespace }) else {
            return []
        }
        let folded = TextFold.folded(needle)
        var hits: [SearchHit] = articles.compactMap { article in
            guard article.searchText.contains(folded) else {
                return nil
            }
            let text = article.excerpt ?? article.material.byline ?? article.material.sourceURL?.host() ?? ""
            return SearchHit(itemID: article.material.id, source: .material, text: text)
        }
        var pending = hits
        var lastFlush = ContinuousClock.now
        func flush() async {
            guard !pending.isEmpty else {
                return
            }
            let chunk = pending
            pending = []
            await yield(chunk)
            lastFlush = .now
        }
        await flush()
        var cancelled = false
        await withTaskGroup(of: Entry?.self, returning: Void.self) { group in
            for materialID in bodies.keys {
                group.addTask { self.entry(for: materialID) }
            }
            for await entry in group {
                if Task.isCancelled {
                    cancelled = true
                    break
                }
                guard let entry else {
                    continue
                }
                var found: [SearchHit] = []
                for paragraph in entry.body.paragraphs where entry.foldedParagraphs[paragraph.piece]?.contains(folded) == true {
                    found += Self.matches(in: paragraph.markdown, of: needle, itemID: entry.body.materialID, source: .text, piece: paragraph.piece)
                }
                for (index, cue) in entry.body.cues.enumerated() where entry.foldedCues[index]?.contains(folded) == true {
                    found += Self.matches(in: cue.text, of: needle, itemID: entry.body.materialID, source: .transcript, seconds: cue.seconds)
                }
                if !found.isEmpty {
                    hits += found
                    pending += found
                    if pending.count >= 150 || ContinuousClock.now - lastFlush >= .milliseconds(120) {
                        await flush()
                    }
                }
            }
        }
        if cancelled {
            return []
        }
        var noted: [SearchHit] = []
        for annotation in annotations {
            if !annotation.note.isEmpty, TextFold.folded(annotation.note).contains(folded) {
                noted += Self.matches(in: annotation.note, of: needle, itemID: annotation.materialID, source: .annotation, piece: annotation.piece)
            } else if let mark = annotation.marks.first(where: { TextFold.folded($0.quote).contains(folded) }) {
                noted += Self.matches(in: mark.quote, of: needle, itemID: annotation.materialID, source: .annotation, piece: annotation.piece)
            } else if TextFold.folded(annotation.text).contains(folded) {
                noted += Self.matches(in: annotation.text, of: needle, itemID: annotation.materialID, source: .annotation, piece: annotation.piece)
            }
        }
        if !noted.isEmpty {
            hits += noted
            pending += noted
        }
        await flush()
        let order = Dictionary(uniqueKeysWithValues: SearchSource.allCases.enumerated().map { ($1, $0) })
        return hits.sorted { left, right in
            let leftOrder = order[left.source] ?? 0
            let rightOrder = order[right.source] ?? 0
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            let leftDate = addedAt[left.itemID] ?? .distantPast
            let rightDate = addedAt[right.itemID] ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            if left.piece != right.piece {
                return (left.piece ?? 0) < (right.piece ?? 0)
            }
            return (left.seconds ?? 0) < (right.seconds ?? 0)
        }
    }

    private static func matches(in text: String, of needle: String, itemID: String, source: SearchSource, piece: Int? = nil, seconds: Double? = nil) -> [SearchHit] {
        ReadingSearch.spans(of: needle, in: text).map { span in
            let excerpt = SearchExcerpt.around(text, span: span)
            return SearchHit(itemID: itemID, source: source, piece: piece, seconds: seconds, text: excerpt.text, span: excerpt.span)
        }
    }
}
