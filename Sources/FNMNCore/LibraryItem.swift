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

public struct SourceRef: Hashable, Sendable {
    public let name: String
    public let homepage: URL?
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

public struct AlbumSummary: Identifiable, Hashable, Sendable {
    public let name: String
    public let count: Int
    /// Up to three materials, the newest first, fanned out on the album's tile.
    public let front: [LibraryItem]
    public var id: String { name }
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

    public func continueItems(_ progress: ReadingProgress, limit: Int = 4) -> [LibraryItem] {
        let opened = items.compactMap { item -> (LibraryItem, Date)? in
            guard let reading = progress.readings[item.id], !reading.isRead, let date = reading.openedAt else { return nil }
            return (item, date)
        }
        return opened.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    public var unsortedItems: [LibraryItem] {
        items.filter { albums(of: $0.id).isEmpty }
    }

    public var albumSummaries: [AlbumSummary] {
        let members = items
        return albums.map { name in
            let inside = members.filter { albums(of: $0.id).contains(name) }
            return AlbumSummary(name: name, count: inside.count, front: Array(inside.prefix(3)))
        }
    }

    /// The source of one material without building every tile, for the reader's header.
    public func source(of itemID: String) -> SourceRef? {
        guard let article = articles.first(where: { $0.material.id == itemID }) else { return nil }
        guard let sourceURL = article.material.sourceURL else { return article.material.authors }
        let key = SourceIndex.key(sourceURL)
        let saved = browserCatalog?.sources.first { source in
            source.materials.contains { ([$0.url] + $0.savedURLs).map(SourceIndex.key).contains(key) }
        }
        var sites = SourceIndex(catalog: nil)
        return saved.map { SourceRef(name: $0.name, homepage: URL(string: $0.url)) } ?? sites.source(for: sourceURL)
    }

    public func items(inAlbum name: String) -> [LibraryItem] {
        items.filter { albums(of: $0.id).contains(name) }
    }

    public func items(fromSource name: String) -> [LibraryItem] {
        items.filter { $0.source?.name == name }
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
        var sources = SourceIndex(catalog: browserCatalog)
        return articles.map { article in
            let material = article.material
            return LibraryItem(
                id: material.id,
                kind: LibraryItem.Kind(material.kind),
                title: material.title,
                source: material.sourceURL.map { sources.source(for: $0) } ?? material.authors,
                originalURL: material.sourceURL,
                addedAt: addedAt[material.id],
                excerpt: article.excerpt,
                cover: article.cover
            )
        }
        .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
    }
}

/// Finds the author, blog or channel a saved link came from.
struct SourceIndex {
    private var sources: [String: SourceRef] = [:]

    init(catalog: BrowserCatalog?) {
        for source in catalog?.sources ?? [] {
            let ref = SourceRef(name: source.name, homepage: URL(string: source.url))
            for material in source.materials {
                for url in [material.url] + material.savedURLs {
                    sources[Self.key(url)] = ref
                }
            }
        }
    }

    /// A prepared material's address is already parsed, so it is not parsed again for every tile;
    /// a site without a saved source is worked out once per host.
    mutating func source(for url: URL) -> SourceRef? {
        if let known = sources[Self.key(url)] { return known }
        guard let host = url.host() else { return nil }
        let site = "site:\(url.scheme ?? "https")://\(host)"
        if let known = sources[site] { return known }
        let ref = SourceRef(name: Self.siteName(host), homepage: URL(string: "\(url.scheme ?? "https")://\(host)"))
        sources[site] = ref
        return ref
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

    /// YouTube links differ in shape but not in video; everything else compares by address.
    static func key(_ url: String) -> String {
        URL(string: url).map(key) ?? url
    }

    static func key(_ url: URL) -> String {
        if let video = YouTube.videoID(in: url) { return "youtube:\(video)" }
        return url.absoluteString
    }
}
