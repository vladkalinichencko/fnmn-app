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
    /// Albums in the order they were made, the rest by name, months newest first.
    case standard, name, size, recent
}

/// The order of the materials on the screen of one album, publisher, type or month.
public enum ItemSort: String, CaseIterable, Hashable, Sendable {
    case newest, oldest, title
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
    public var id: String { "\(grouping.rawValue):\(key)" }
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

    public func continueItems(_ progress: ReadingProgress) -> [LibraryItem] {
        let opened = items.compactMap { item -> (LibraryItem, Date)? in
            guard let reading = progress.readings[item.id], !reading.isRead, let date = reading.openedAt else { return nil }
            return (item, date)
        }
        return opened.sorted { $0.1 > $1.1 }.map(\.0)
    }

    public var unsortedItems: [LibraryItem] {
        items.filter { albums(of: $0.id).isEmpty }
    }

    public var albumSummaries: [AlbumSummary] {
        let members = items
        return albums.map { name in
            let inside = members.filter { albums(of: $0.id).contains(name) }
            return AlbumSummary(grouping: .albums, key: name, name: name, count: inside.count, front: Array(inside.prefix(3)))
        }
    }

    /// The Collections section: the same materials gathered by album, publisher, type or month added.
    /// Only albums can be empty; the other groupings list what exists.
    public func groups(by grouping: LibraryGrouping, sortedBy sort: GroupSort) -> [AlbumSummary] {
        var summaries: [AlbumSummary]
        if grouping == .albums {
            summaries = albumSummaries
        } else {
            var order: [String] = []
            var names: [String: String] = [:]
            var members: [String: [LibraryItem]] = [:]
            for item in items {
                guard let (key, name) = Self.group(of: item, by: grouping) else { continue }
                if members[key] == nil { order.append(key) }
                names[key] = name
                members[key, default: []].append(item)
            }
            summaries = order.map { key in
                let inside = members[key] ?? []
                return AlbumSummary(grouping: grouping, key: key, name: names[key] ?? key, count: inside.count, front: Array(inside.prefix(3)))
            }
        }
        func byName(_ a: AlbumSummary, _ b: AlbumSummary) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        switch sort {
        case .standard:
            if grouping == .months { summaries.sort { $0.key > $1.key } } else if grouping != .albums { summaries.sort(by: byName) }
        case .name:
            if grouping == .months { summaries.sort { $0.key > $1.key } } else { summaries.sort(by: byName) }
        case .size:
            summaries.sort { $0.count != $1.count ? $0.count > $1.count : byName($0, $1) }
        case .recent:
            let newest = { (group: AlbumSummary) in group.front.first?.addedAt ?? .distantPast }
            summaries.sort { newest($0) != newest($1) ? newest($0) > newest($1) : byName($0, $1) }
        }
        return summaries
    }

    /// The materials of one album, publisher, type or month in the reader's order, in sections when grouped.
    public static func arrange(_ items: [LibraryItem], sortedBy sort: ItemSort, groupedBy grouping: ItemGrouping) -> [ItemSection] {
        func sorted(_ items: [LibraryItem]) -> [LibraryItem] {
            items.sorted { a, b in
                let titles = a.title.localizedStandardCompare(b.title)
                switch sort {
                case .title where titles != .orderedSame: return titles == .orderedAscending
                case .newest where a.addedAt != b.addedAt: return (a.addedAt ?? .distantPast) > (b.addedAt ?? .distantPast)
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
            if members[key] == nil { order.append(key) }
            names[key] = name
            members[key, default: []].append(item)
        }
        let keys = by == .months ? order.sorted(by: >) : order.sorted { (names[$0] ?? "").localizedStandardCompare(names[$1] ?? "") == .orderedAscending }
        return keys.map { ItemSection(id: $0, title: names[$0], items: sorted(members[$0] ?? [])) }
    }

    public func items(in grouping: LibraryGrouping, key: String) -> [LibraryItem] {
        grouping == .albums ? items(inAlbum: key) : items.filter { Self.group(of: $0, by: grouping)?.key == key }
    }

    public func groupName(_ grouping: LibraryGrouping, key: String) -> String {
        groups(by: grouping, sortedBy: .standard).first { $0.key == key }?.name ?? key
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

    public func items(inAlbum name: String) -> [LibraryItem] {
        items.filter { albums(of: $0.id).contains(name) }
    }

    public func items(fromSource id: String) -> [LibraryItem] {
        items.filter { $0.source?.id == id }
    }

    public var archivedItems: [LibraryItem] {
        allItems.filter { isArchived($0.id) }
    }

    /// Titles, authors, sources, albums and section headings; the body text is not searched.
    public func items(matching query: String) -> [LibraryItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        let folded = ArticleEntry.folded(needle)
        func hit(_ text: String) -> Bool { ArticleEntry.folded(text).contains(folded) }
        let articleHits = Set(articles.filter { $0.searchText.contains(folded) }.map(\.material.id))
        // Albums and sources repeat across tiles, so each name is tested once.
        let albumHits = Set(albums.filter(hit))
        var sourceHits: [String: Bool] = [:]
        return items.filter { item in
            if articleHits.contains(item.id) { return true }
            if albums(of: item.id).contains(where: albumHits.contains) { return true }
            guard let source = item.source?.name else { return false }
            if let known = sourceHits[source] { return known }
            let found = hit(source)
            sourceHits[source] = found
            return found
        }
    }

    /// Highlights and notes grouped by material; the most recently touched material and annotation come first.
    public var annotationGroups: [AnnotationGroup] {
        let byItem = Dictionary(grouping: annotations, by: \.materialID)
        let known = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = byItem.compactMap { itemID, annotations -> AnnotationGroup? in
            guard let item = known[itemID] else { return nil }
            let sorted = annotations.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            return AnnotationGroup(item: item, annotations: sorted)
        }
        return groups.sorted {
            ($0.annotations.first?.updatedAt ?? .distantPast) > ($1.annotations.first?.updatedAt ?? .distantPast)
        }
    }

    private var allItems: [LibraryItem] {
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
            if a != b { return a > b }
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
            if let homepage = ref.homepage { enter(ref, at: homepage) }
        }
        for page in declared {
            guard let host = page.homepage.host() else { continue }
            enter(SourceRef(name: page.name ?? Self.siteName(host), homepage: page.homepage), at: page.homepage)
        }
    }

    /// A prepared material's address is already parsed, so it is not parsed again for every tile;
    /// a site without a publisher of its own is worked out once per host.
    mutating func source(for url: URL) -> SourceRef? {
        if let known = saved[Self.key(url)] { return known }
        guard let host = url.host(), let hostKey = Self.hostKey(url) else { return nil }
        let path = Self.segments(url)
        let above = homes[hostKey]?.filter { path.starts(with: $0.path) }
        if let home = above?.max(by: { $0.path.count < $1.path.count }) { return home.ref }
        if let known = sites[hostKey] { return known }
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
        if labels.suffix(2).joined(separator: ".") == "github.io" { return String(labels[0]) }
        let secondLevel = ["co", "com", "org", "ac", "net"]
        if labels.count > 2, secondLevel.contains(String(labels[labels.count - 2])) { return String(labels[labels.count - 3]) }
        return String(labels[labels.count - 2])
    }

    /// YouTube links differ in shape but not in video; everything else compares by address, without the
    /// `#fragment` that only scrolls the page.
    static func key(_ url: String) -> String {
        URL(string: url).map(key) ?? url
    }

    static func key(_ url: URL) -> String {
        if let video = YouTube.videoID(in: url) { return "youtube:\(video)" }
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
