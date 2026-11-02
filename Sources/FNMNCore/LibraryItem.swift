import Foundation

/// One material as every screen sees it: an article, video or book, or a link nothing could be made of.
public struct LibraryItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case article, video, book, link }

    public let id: String
    public let kind: Kind
    public let title: String
    public let source: SourceRef?
    public let originalURL: URL?
    public let addedAt: Date?
    public let excerpt: String?
    public let cover: Cover?
}

public struct SourceRef: Hashable, Identifiable, Sendable {
    public let name: String
    public let homepage: URL?

    /// Sources are one when they stand on the same page, whatever they are called; one with no page, a book's
    /// authors, is known by its name.
    public var id: String { homepage?.absoluteString ?? name }
}

extension LibraryItem.Kind {
    init(_ kind: Material.Kind) {
        self = switch kind {
        case .article: .article
        case .video: .video
        case .book: .book
        case .link: .link
        }
    }
}

extension Material {
    /// A material made from a file has no site behind it, so its authors stand where an article's site does.
    var authors: SourceRef? {
        byline.map { SourceRef(name: $0, homepage: nil) }
    }
}

public enum Cover: Codable, Hashable, Sendable {
    case articleFile(materialID: String, path: String)
    /// The small cover picture the app keeps for a material that lives in iCloud.
    case stored(materialID: String)
    case remote(URL)
}

/// What the Collections section gathers materials by.
public enum LibraryGrouping: String, CaseIterable, Hashable, Sendable {
    case albums, publishers, types, months
}

public enum GroupSort: String, CaseIterable, Hashable, Sendable {
    /// Albums in the order they were made, the rest by name, months newest first. `recent` puts first the group
    /// a material was added to last, `opened` the one opened last, itself or through one of its materials.
    case standard, name, size, recent, opened
}

/// The order of the materials on the screen of one album, publisher, type or month. `opened` puts the material
/// opened last first, and those never opened after them, newest first.
public enum ItemSort: String, CaseIterable, Hashable, Sendable {
    case newest, oldest, title, opened
}

public enum ItemGrouping: String, CaseIterable, Hashable, Sendable {
    case none, publishers, types, months

    var grouping: LibraryGrouping? {
        switch self {
        case .none: nil
        case .publishers: .publishers
        case .types: .types
        case .months: .months
        }
    }
}

public struct ItemSection: Identifiable, Sendable {
    public let id: String
    /// Nil when the screen is not grouped.
    public let title: String?
    public let items: [LibraryItem]
}

/// One tile of the Collections section: an album, or a publisher, a type or a month the materials are gathered by.
public struct AlbumSummary: Identifiable, Hashable, Sendable {
    public let grouping: LibraryGrouping
    /// What finds the group again: an album's name, a source's id, a type's name or a month as `2026-09`.
    public let key: String
    public let name: String
    public let count: Int
    /// Up to three materials, the newest first, fanned out on the group's tile.
    public let front: [LibraryItem]
    public var id: String { Self.id(grouping, key) }

    /// The id of a group without its summary, for a screen that knows only what it shows.
    public static func id(_ grouping: LibraryGrouping, _ key: String) -> String { "\(grouping.rawValue):\(key)" }
}

public struct AnnotationGroup: Identifiable, Sendable {
    public let item: LibraryItem
    public let annotations: [Annotation]
    public var id: String { item.id }
}

extension LibrarySnapshot {
    /// Every material outside the archive, newest first.
    public var items: [LibraryItem] {
        allItems.filter { !isArchived($0.id) }
    }

    public func item(_ id: String) -> LibraryItem? {
        allItems.first { $0.id == id }
    }

    /// `among` takes the materials `LibraryModel` has collected; nil collects them for this call.
    public func continueItems(_ progress: ReadingProgress, among candidates: [LibraryItem]? = nil) -> [LibraryItem] {
        let opened = (candidates ?? items).compactMap { item -> (LibraryItem, Date)? in
            guard let reading = progress.readings[item.id], !reading.isRead, let date = reading.openedAt else { return nil }
            return (item, date)
        }
        return opened.sorted { $0.1 > $1.1 }.map(\.0)
    }

    public var unsortedItems: [LibraryItem] { unsortedItems() }

    public func unsortedItems(among candidates: [LibraryItem]? = nil) -> [LibraryItem] {
        (candidates ?? items).filter { albums(of: $0.id).isEmpty }
    }

    public var albumSummaries: [AlbumSummary] { albumSummaries() }

    /// One pass over the materials, each sorted into its albums, instead of a scan per album.
    public func albumSummaries(among candidates: [LibraryItem]? = nil) -> [AlbumSummary] {
        let members = candidates ?? items
        var byAlbum: [String: [LibraryItem]] = [:]
        for item in members {
            for name in albums(of: item.id) {
                byAlbum[name, default: []].append(item)
            }
        }
        return albums.map { name in
            let inside = byAlbum[name] ?? []
            return AlbumSummary(grouping: .albums, key: name, name: name, count: inside.count, front: Array(inside.prefix(3)))
        }
    }

    /// The Collections section: the same materials gathered by album, publisher, type or month added.
    /// Only albums can be empty; the other groupings list what exists.
    public func groups(by grouping: LibraryGrouping, sortedBy sort: GroupSort, progress: ReadingProgress = ReadingProgress(), among candidates: [LibraryItem]? = nil) -> [AlbumSummary] {
        let members = candidates ?? items
        var summaries: [AlbumSummary]
        if grouping == .albums {
            summaries = albumSummaries(among: members)
        } else {
            var order: [String] = []
            var names: [String: String] = [:]
            var membersByGroup: [String: [LibraryItem]] = [:]
            for item in members {
                guard let (key, name) = Self.group(of: item, by: grouping) else { continue }
                if membersByGroup[key] == nil {
                    order.append(key)
                }
                names[key] = name
                membersByGroup[key, default: []].append(item)
            }
            summaries = order.map { key in
                let inside = membersByGroup[key] ?? []
                return AlbumSummary(grouping: grouping, key: key, name: names[key] ?? key, count: inside.count, front: Array(inside.prefix(3)))
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
            for item in members {
                guard let date = progress.readings[item.id]?.openedAt else { continue }
                let keys = grouping == .albums ? albums(of: item.id) : Self.group(of: item, by: grouping).map { [$0.key] } ?? []
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

    /// The materials of one album, publisher, type or month in the reader's order, in sections when grouped.
    /// `opened` gives when each material was last opened, for sorting by it.
    public static func arrange(
        _ items: [LibraryItem], sortedBy sort: ItemSort, groupedBy grouping: ItemGrouping, opened: [String: Date] = [:]
    ) -> [ItemSection] {
        func sorted(_ items: [LibraryItem]) -> [LibraryItem] {
            items.sorted { a, b in
                let titles = a.title.localizedStandardCompare(b.title)
                switch sort {
                case .title where titles != .orderedSame: return titles == .orderedAscending
                case .opened where opened[a.id] != opened[b.id]: return (opened[a.id] ?? .distantPast) > (opened[b.id] ?? .distantPast)
                case .newest where a.addedAt != b.addedAt, .opened where a.addedAt != b.addedAt:
                    return (a.addedAt ?? .distantPast) > (b.addedAt ?? .distantPast)
                case .oldest where a.addedAt != b.addedAt: return (a.addedAt ?? .distantPast) < (b.addedAt ?? .distantPast)
                default: return titles == .orderedSame ? a.id < b.id : titles == .orderedAscending
                }
            }
        }
        guard let by = grouping.grouping else { return [ItemSection(id: "all", title: nil, items: sorted(items))] }
        var order: [String] = []
        var names: [String: String] = [:]
        var members: [String: [LibraryItem]] = [:]
        for item in items {
            let (key, name) = group(of: item, by: by) ?? ("", "Other")
            if members[key] == nil {
                order.append(key)
            }
            names[key] = name
            members[key, default: []].append(item)
        }
        let keys = by == .months ? order.sorted(by: >) : order.sorted { (names[$0] ?? "").localizedStandardCompare(names[$1] ?? "") == .orderedAscending }
        return keys.map { ItemSection(id: $0, title: names[$0], items: sorted(members[$0] ?? [])) }
    }

    public func items(in grouping: LibraryGrouping, key: String, among candidates: [LibraryItem]? = nil) -> [LibraryItem] {
        let members = candidates ?? items
        return grouping == .albums ? items(inAlbum: key, among: members) : members.filter { Self.group(of: $0, by: grouping)?.key == key }
    }

    public func groupName(_ grouping: LibraryGrouping, key: String, among candidates: [LibraryItem]? = nil) -> String {
        groups(by: grouping, sortedBy: .standard, among: candidates).first { $0.key == key }?.name ?? key
    }

    private static func group(of item: LibraryItem, by grouping: LibraryGrouping) -> (key: String, name: String)? {
        switch grouping {
        case .albums:
            return nil
        case .publishers:
            return item.source.map { ($0.id, $0.name) }
        case .types:
            switch item.kind {
            case .article: return ("article", "Articles")
            case .video: return ("video", "Videos")
            case .book: return ("book", "Books")
            case .link: return ("link", "Links")
            }
        case .months:
            guard let date = item.addedAt else { return ("0000", "Earlier") }
            let parts = Calendar.current.dateComponents([.year, .month], from: date)
            return (String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0), date.formatted(.dateTime.month(.wide).year()))
        }
    }

    /// The source of one material without building every tile, for the reader's header.
    public func source(of itemID: String) -> SourceRef? {
        guard let article = articles.first(where: { $0.material.id == itemID }) else { return nil }
        guard let sourceURL = article.material.sourceURL else { return article.material.authors }
        var index = SourceIndex(catalog: browserCatalog, declared: articles.compactMap(\.material.source))
        return index.source(for: sourceURL)
    }

    public func items(inAlbum name: String, among candidates: [LibraryItem]? = nil) -> [LibraryItem] {
        (candidates ?? items).filter { albums(of: $0.id).contains(name) }
    }

    public func items(fromSource id: String, among candidates: [LibraryItem]? = nil) -> [LibraryItem] {
        (candidates ?? items).filter { $0.source?.id == id }
    }

    public var archivedItems: [LibraryItem] {
        allItems.filter { isArchived($0.id) }
    }

    /// Titles, authors, sources, albums and section headings; the body text is not searched.
    public func items(matching query: String, among candidates: [LibraryItem]? = nil) -> [LibraryItem] {
        let candidates = candidates ?? items
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return candidates }
        let folded = ArticleEntry.folded(needle)
        func hit(_ text: String) -> Bool { ArticleEntry.folded(text).contains(folded) }
        let articleHits = Set(articles.filter { $0.searchText.contains(folded) }.map(\.material.id))
        // Albums and sources repeat across tiles, so each name is tested once.
        let albumHits = Set(albums.filter(hit))
        var sourceHits: [String: Bool] = [:]
        return candidates.filter { item in
            if articleHits.contains(item.id) {
                return true
            }
            if albums(of: item.id).contains(where: albumHits.contains) {
                return true
            }
            guard let source = item.source?.name else { return false }
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
        annotationGroups(among: allItems)
    }

    public func annotationGroups(among candidates: [LibraryItem]) -> [AnnotationGroup] {
        let byItem = Dictionary(grouping: annotations, by: \.materialID)
        let known = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = byItem.compactMap { itemID, annotations -> AnnotationGroup? in
            guard let item = known[itemID] else { return nil }
            let sorted = annotations.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            return AnnotationGroup(item: item, annotations: sorted)
        }
        return groups.sorted {
            ($0.annotations.first?.updatedAt ?? .distantPast) > ($1.annotations.first?.updatedAt ?? .distantPast)
        }
    }

    /// The annotations a search finds: all of a material the material search finds, and elsewhere those whose
    /// paragraph or note holds the query.
    public func annotationGroups(matching query: String, among: [LibraryItem]? = nil) -> [AnnotationGroup] {
        let groups = annotationGroups(among: among ?? allItems)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return groups }
        let folded = ArticleEntry.folded(needle)
        let found = Set(items(matching: needle, among: among ?? allItems).map(\.id))
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

    /// Everything, newest first. Expensive to build: `LibraryModel` collects it once per catalog change.
    public var allItems: [LibraryItem] {
        var sources = SourceIndex(catalog: browserCatalog, declared: articles.compactMap(\.material.source))
        return articles.map { article in
            let material = article.material
            return LibraryItem(
                id: material.id,
                kind: LibraryItem.Kind(material.kind),
                title: material.title,
                source: material.sourceURL.map { sources.source(for: $0) } ?? material.authors,
                originalURL: material.sourceURL,
                // The moment the server wrote the delivery, to the second; the moment this device imported it is
                // the same for a whole folder read at once, and says nothing of the order they were saved in.
                addedAt: article.deliveredAt ?? addedAt[material.id],
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

/// Finds the author, blog or channel a saved link came from: the one the browser catalog saved that very
/// page under, else the nearest page above it that stands for a publisher (the catalog's, or one the server
/// found for another article), else its site. A link added later therefore joins the publisher its neighbours
/// already have.
struct SourceIndex {
    /// A publisher's page and the path under which its articles lie.
    private struct Home {
        let path: [String]
        let ref: SourceRef
    }

    private var saved: [String: SourceRef] = [:]
    private var homes: [String: [Home]] = [:]
    private var sites: [String: SourceRef] = [:]

    /// The catalog's sources are entered first, so a blog it names keeps its name over one a page calls itself.
    init(catalog: BrowserCatalog?, declared: [PageSource] = []) {
        for source in catalog?.sources ?? [] {
            let ref = SourceRef(name: source.name, homepage: URL(string: source.url))
            for material in source.materials {
                for url in [material.url] + material.savedURLs {
                    saved[Self.key(url)] = ref
                }
            }
            if let homepage = ref.homepage {
                enter(ref, at: homepage)
            }
        }
        for page in declared {
            guard let host = page.homepage.host() else { continue }
            enter(SourceRef(name: page.name ?? Self.siteName(host), homepage: page.homepage), at: page.homepage)
        }
    }

    /// A prepared material's address is already parsed, so it is not parsed again for every tile;
    /// a site without a publisher of its own is worked out once per host.
    mutating func source(for url: URL) -> SourceRef? {
        if let known = saved[Self.key(url)] {
            return known
        }
        guard let host = url.host(), let hostKey = Self.hostKey(url) else { return nil }
        let path = Self.segments(url)
        let above = homes[hostKey]?.filter { path.starts(with: $0.path) }
        if let home = above?.max(by: { $0.path.count < $1.path.count }) {
            return home.ref
        }
        if let known = sites[hostKey] {
            return known
        }
        let ref = SourceRef(name: Self.siteName(host), homepage: URL(string: "\(url.scheme ?? "https")://\(host)"))
        sites[hostKey] = ref
        return ref
    }

    private mutating func enter(_ ref: SourceRef, at page: URL) {
        guard let host = Self.hostKey(page) else { return }
        let path = Self.segments(page)
        guard !homes[host, default: []].contains(where: { $0.path == path }) else { return }
        homes[host, default: []].append(Home(path: path, ref: ref))
    }

    /// `example.com` for www.example.com, so a page and its `www.` twin are one site.
    private static func hostKey(_ url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func segments(_ url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" }
    }

    /// The core of a host: `example` for example.com, www.example.co.uk and example.github.io.
    static func siteName(_ host: String) -> String {
        let labels = host.split(separator: ".").filter { $0 != "www" }
        guard labels.count > 1 else { return host }
        if labels.suffix(2).joined(separator: ".") == "github.io" {
            return String(labels[0])
        }
        let secondLevel = ["co", "com", "org", "ac", "net"]
        if labels.count > 2, secondLevel.contains(String(labels[labels.count - 2])) {
            return String(labels[labels.count - 3])
        }
        return String(labels[labels.count - 2])
    }

    /// YouTube links differ in shape but not in video; everything else compares by address, without the
    /// `#fragment` that only scrolls the page.
    static func key(_ url: String) -> String {
        URL(string: url).map(key) ?? url
    }

    static func key(_ url: URL) -> String {
        if let video = YouTube.videoID(in: url) {
            return "youtube:\(video)"
        }
        return url.withoutFragment.absoluteString
    }
}

extension URL {
    /// The page itself: a link to a heading or a paragraph of it names the same material.
    public var withoutFragment: URL {
        guard fragment != nil, var parts = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        parts.fragment = nil
        return parts.url ?? self
    }
}
