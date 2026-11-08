import Foundation

/// The materials as screens list them. Building walks the whole catalog and sorts it, so `LibraryModel`
/// builds it once per change, and every query here is a filter or a sort over what it already holds.
public struct LibraryQueries: Sendable {
    /// Everything, newest first.
    public let allItems: [LibraryItem]
    /// Every material outside the archive, newest first.
    public let items: [LibraryItem]
    public let archivedItems: [LibraryItem]
    private let snapshot: LibrarySnapshot

    public init(_ snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
        allItems = Self.collect(snapshot)
        items = allItems.filter { !snapshot.isArchived($0.id) }
        archivedItems = allItems.filter { snapshot.isArchived($0.id) }
    }

    public func item(_ id: String) -> LibraryItem? {
        allItems.first { $0.id == id }
    }

    public func continueItems(_ progress: ReadingProgress) -> [LibraryItem] {
        let opened = items.compactMap { item -> (LibraryItem, Date)? in
            guard let reading = progress.readings[item.id], !reading.isRead, let date = reading.openedAt else {
                return nil
            }
            return (item, date)
        }
        return opened.sorted { $0.1 > $1.1 }.map(\.0)
    }

    public var unsortedItems: [LibraryItem] {
        items.filter { snapshot.albums(of: $0.id).isEmpty }
    }

    /// One pass over the materials, each sorted into its albums, instead of a scan per album.
    public var albumSummaries: [AlbumSummary] {
        var byAlbum: [String: [LibraryItem]] = [:]
        for item in items {
            for name in snapshot.albums(of: item.id) {
                byAlbum[name, default: []].append(item)
            }
        }
        return snapshot.albums.map { name in
            let inside = byAlbum[name] ?? []
            return AlbumSummary(grouping: .albums, key: name, name: name, count: inside.count, front: Array(inside.prefix(3)))
        }
    }

    /// The Collections section: the same materials gathered by album, publisher, type or month added.
    /// Only albums can be empty; the other groupings list what exists.
    public func groups(by grouping: LibraryGrouping, sortedBy sort: GroupSort, progress: ReadingProgress = ReadingProgress()) -> [AlbumSummary] {
        var summaries: [AlbumSummary]
        if grouping == .albums {
            summaries = albumSummaries
        } else {
            summaries = OrderedGroups.of(items, by: { Self.group(of: $0, by: grouping) }).map { group in
                AlbumSummary(
                    grouping: grouping,
                    key: group.key,
                    name: group.name,
                    count: group.items.count,
                    front: Array(group.items.prefix(3))
                )
            }
        }
        func byName(_ a: AlbumSummary, _ b: AlbumSummary) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        switch sort {
        case .standard:
            if grouping == .months {
                summaries.sort { $0.key > $1.key }
            } else if grouping != .albums {
                summaries.sort(by: byName)
            }
        case .name:
            if grouping == .months {
                summaries.sort { $0.key > $1.key }
            } else {
                summaries.sort(by: byName)
            }
        case .size:
            summaries.sort { $0.count != $1.count ? $0.count > $1.count : byName($0, $1) }
        case .recent:
            let newest = { (group: AlbumSummary) in group.front.first?.addedAt ?? .distantPast }
            summaries.sort { newest($0) != newest($1) ? newest($0) > newest($1) : byName($0, $1) }
        case .opened:
            var opened = progress.groupsOpened
            for item in items {
                guard let date = progress.readings[item.id]?.openedAt else {
                    continue
                }
                let keys = grouping == .albums ? snapshot.albums(of: item.id) : Self.group(of: item, by: grouping).map { [$0.key] } ?? []
                for key in keys {
                    let id = AlbumSummary.id(grouping, key)
                    opened[id] = max(opened[id] ?? .distantPast, date)
                }
            }
            let last = { (group: AlbumSummary) in opened[group.id] ?? .distantPast }
            summaries.sort { last($0) != last($1) ? last($0) > last($1) : byName($0, $1) }
        }
        return summaries
    }

    public func items(in grouping: LibraryGrouping, key: String) -> [LibraryItem] {
        if grouping == .albums {
            return items(inAlbum: key)
        }
        return items.filter { Self.group(of: $0, by: grouping)?.key == key }
    }

    public func groupName(_ grouping: LibraryGrouping, key: String) -> String {
        groups(by: grouping, sortedBy: .standard).first { $0.key == key }?.name ?? key
    }

    public func items(inAlbum name: String) -> [LibraryItem] {
        items.filter { snapshot.albums(of: $0.id).contains(name) }
    }

    public func items(fromSource id: String) -> [LibraryItem] {
        items.filter { $0.source?.id == id }
    }

    /// Titles, authors, sources, albums and section headings; the body text is not searched.
    public func items(matching query: String) -> [LibraryItem] {
        search(query, in: items)
    }

    /// The same search over the materials a screen already shows, such as one album's.
    public func search(_ query: String, in candidates: [LibraryItem]) -> [LibraryItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return candidates
        }
        let folded = ArticleEntry.folded(needle)
        func hit(_ text: String) -> Bool {
            ArticleEntry.folded(text).contains(folded)
        }
        let articleHits = Set(snapshot.articles.filter { $0.searchText.contains(folded) }.map(\.material.id))
        // Albums and sources repeat across tiles, so each name is tested once.
        let albumHits = Set(snapshot.albums.filter(hit))
        var sourceHits: [String: Bool] = [:]
        return candidates.filter { item in
            if articleHits.contains(item.id) {
                return true
            }
            if snapshot.albums(of: item.id).contains(where: albumHits.contains) {
                return true
            }
            guard let source = item.source?.name else {
                return false
            }
            if let known = sourceHits[source] {
                return known
            }
            let found = hit(source)
            sourceHits[source] = found
            return found
        }
    }

    /// Highlights and notes grouped by material; the most recently touched material and annotation come first.
    public var annotationGroups: [AnnotationGroup] {
        let byItem = Dictionary(grouping: snapshot.annotations, by: \.materialID)
        let known = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = byItem.compactMap { itemID, annotations -> AnnotationGroup? in
            guard let item = known[itemID] else {
                return nil
            }
            let sorted = annotations.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            return AnnotationGroup(item: item, annotations: sorted)
        }
        return groups.sorted {
            ($0.annotations.first?.updatedAt ?? .distantPast) > ($1.annotations.first?.updatedAt ?? .distantPast)
        }
    }

    /// The annotations a search finds: all of a material the material search finds, and elsewhere those whose
    /// paragraph or note holds the query.
    public func annotationGroups(matching query: String) -> [AnnotationGroup] {
        let groups = annotationGroups
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return groups
        }
        let folded = ArticleEntry.folded(needle)
        let found = Set(search(needle, in: allItems).map(\.id))
        return groups.compactMap { group in
            if found.contains(group.id) {
                return group
            }
            let hits = group.annotations.filter {
                ArticleEntry.folded($0.text).contains(folded) || ArticleEntry.folded($0.note).contains(folded)
            }
            return hits.isEmpty ? nil : AnnotationGroup(item: group.item, annotations: hits)
        }
    }

    /// The materials of one album, publisher, type or month in the reader's order, in sections when grouped.
    /// `opened` gives when each material was last opened, for sorting by it.
    public static func arrange(
        _ items: [LibraryItem], sortedBy sort: ItemSort, groupedBy grouping: ItemGrouping, opened: [String: Date] = [:]
    ) -> [ItemSection] {
        func sorted(_ items: [LibraryItem]) -> [LibraryItem] {
            items.sorted { a, b in
                let titles = a.title.localizedStandardCompare(b.title)
                switch sort {
                case .title where titles != .orderedSame:
                    return titles == .orderedAscending
                case .opened where opened[a.id] != opened[b.id]:
                    return (opened[a.id] ?? .distantPast) > (opened[b.id] ?? .distantPast)
                case .newest where a.addedAt != b.addedAt, .opened where a.addedAt != b.addedAt:
                    return (a.addedAt ?? .distantPast) > (b.addedAt ?? .distantPast)
                case .oldest where a.addedAt != b.addedAt:
                    return (a.addedAt ?? .distantPast) < (b.addedAt ?? .distantPast)
                default:
                    return titles == .orderedSame ? a.id < b.id : titles == .orderedAscending
                }
            }
        }
        guard let by = grouping.grouping else {
            return [ItemSection(id: "all", title: nil, items: sorted(items))]
        }
        let groups = OrderedGroups.of(items, by: { group(of: $0, by: by) ?? ("", "Other") })
        let ordered = if by == .months {
            groups.sorted { $0.key > $1.key }
        } else {
            groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return ordered.map { ItemSection(id: $0.key, title: $0.name, items: sorted($0.items)) }
    }

    private static func group(of item: LibraryItem, by grouping: LibraryGrouping) -> (key: String, name: String)? {
        switch grouping {
        case .albums:
            return nil
        case .publishers:
            return item.source.map { ($0.id, $0.name) }
        case .types:
            switch item.kind {
            case .article:
                return ("article", "Articles")
            case .video:
                return ("video", "Videos")
            case .book:
                return ("book", "Books")
            case .link:
                return ("link", "Links")
            }
        case .months:
            guard let date = item.addedAt else {
                return ("0000", "Earlier")
            }
            let parts = Calendar.current.dateComponents([.year, .month], from: date)
            return (String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0), date.formatted(.dateTime.month(.wide).year()))
        }
    }

    /// Everything, built from the snapshot: the browser catalog and the declared sources name each publisher.
    private static func collect(_ snapshot: LibrarySnapshot) -> [LibraryItem] {
        var sources = SourceIndex(catalog: snapshot.browserCatalog, declared: snapshot.articles.compactMap(\.material.source))
        return snapshot.articles.map { article in
            let material = article.material
            return LibraryItem(
                id: material.id,
                kind: LibraryItem.Kind(material.kind),
                title: material.title,
                source: material.sourceURL.map { sources.source(for: $0) } ?? material.authors,
                originalURL: material.sourceURL,
                // The moment the server wrote the delivery, to the second; the moment this device imported it is
                // the same for a whole folder read at once, and says nothing of the order they were saved in.
                addedAt: article.deliveredAt ?? snapshot.addedAt[material.id],
                excerpt: article.excerpt,
                cover: article.cover
            )
        }
        .sorted {
            let (a, b) = ($0.addedAt ?? .distantPast, $1.addedAt ?? .distantPast)
            if a != b {
                return a > b
            }
            // A folder import gives a whole batch one date; ties fall back to the title so the order stays put.
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
