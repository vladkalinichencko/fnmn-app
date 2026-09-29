import Foundation

/// One material as every screen sees it: a prepared article, video or book, or a saved link the Mac has not prepared.
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
    public let progress: Double?
    public let isRead: Bool
}

public struct SourceRef: Hashable, Sendable {
    public let name: String
    public let homepage: URL?
}

public enum Cover: Hashable, Sendable {
    case articleFile(materialID: String, path: String)
    case remote(URL)
}

public struct AlbumSummary: Identifiable, Hashable, Sendable {
    public let name: String
    public let count: Int
    /// Up to three covers, the newest first, fanned out on the album's tile.
    public let covers: [Cover]
    public var id: String { name }
}

public struct AnnotationGroup: Identifiable, Sendable {
    public let item: LibraryItem
    public let annotations: [Annotation]
    public var id: String { item.id }
}

extension LibrarySnapshot {
    public static func linkID(_ url: String) -> String { "link:\(url)" }

    /// Every material outside the archive, newest first.
    public var items: [LibraryItem] {
        allItems.filter { !isArchived($0.id) }
    }

    public func item(_ id: String) -> LibraryItem? {
        allItems.first { $0.id == id }
    }

    public func continueItems(limit: Int = 4) -> [LibraryItem] {
        let opened = items.compactMap { item -> (LibraryItem, Date)? in
            guard !item.isRead, let date = readings[item.id]?.openedAt else { return nil }
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
            return AlbumSummary(name: name, count: inside.count, covers: Array(inside.lazy.compactMap(\.cover).prefix(3)))
        }
    }

    /// The source of one material without building every tile, for the reader's header.
    public func source(of itemID: String) -> SourceRef? {
        if let book = books.first(where: { $0.id == itemID }) {
            return book.metadata.authors.first.map { SourceRef(name: $0, homepage: nil) }
        }
        guard let package = packages.first(where: { $0.material.id == itemID }) else { return nil }
        let key = SourceIndex.key(package.material.sourceURL.absoluteString)
        let saved = browserCatalog?.sources.first { source in
            source.materials.contains { ([$0.url] + $0.savedURLs).map(SourceIndex.key).contains(key) }
        }
        return saved.map { SourceRef(name: $0.name, homepage: URL(string: $0.url)) }
            ?? SourceIndex(catalog: nil).source(for: package.material.sourceURL.absoluteString)
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
        let packageHits = Set(packages.filter { $0.matches(needle) }.map(\.material.id))
        let bookHits = Set(books.filter { $0.matches(needle) }.map(\.id))
        return items.filter { item in
            packageHits.contains(item.id) || bookHits.contains(item.id)
                || item.title.localizedStandardContains(needle)
                || item.source?.name.localizedStandardContains(needle) == true
                || albums(of: item.id).contains { $0.localizedStandardContains(needle) }
        }
    }

    /// Highlights and notes grouped by material; the most recently touched material and annotation come first.
    public var annotationGroups: [AnnotationGroup] {
        let byItem = Dictionary(grouping: annotations, by: \.materialID)
        let groups = byItem.compactMap { itemID, annotations -> AnnotationGroup? in
            guard let item = item(itemID) else { return nil }
            let sorted = annotations.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            return AnnotationGroup(item: item, annotations: sorted)
        }
        return groups.sorted {
            ($0.annotations.first?.updatedAt ?? .distantPast) > ($1.annotations.first?.updatedAt ?? .distantPast)
        }
    }

    /// A paragraph is read when it scrolled past the top, or when it lies at or before the reader's "read through here" mark.
    public func isPieceRead(_ piece: Int, of itemID: String, current: Int?) -> Bool {
        if let mark = readThrough[itemID], piece <= mark { return true }
        guard let current else { return false }
        return piece < current
    }

    private var allItems: [LibraryItem] {
        let sources = SourceIndex(catalog: browserCatalog)
        let prepared = packages.map { package in
            LibraryItem(
                id: package.material.id,
                kind: package.material.kind == .video ? .video : .article,
                title: package.material.title,
                source: sources.source(for: package.material.sourceURL.absoluteString),
                originalURL: package.material.sourceURL,
                addedAt: addedAt[package.material.id],
                excerpt: package.material.kind == .video ? package.material.byline : ArticleBody.excerpt(package.body),
                cover: package.cover,
                progress: readings[package.material.id]?.progress,
                isRead: readings[package.material.id]?.isRead ?? false
            )
        }
        let bookItems = books.map { book in
            LibraryItem(
                id: book.id,
                kind: .book,
                title: book.metadata.title,
                source: book.metadata.authors.first.map { SourceRef(name: $0, homepage: nil) },
                originalURL: nil,
                addedAt: addedAt[book.id],
                excerpt: book.metadata.subtitle,
                cover: nil,
                progress: readings[book.id]?.progress,
                isRead: readings[book.id]?.isRead ?? false
            )
        }
        let preparedKeys = Set(packages.map { SourceIndex.key($0.material.sourceURL.absoluteString) })
        let links = (browserCatalog?.sources ?? []).flatMap { source in
            source.materials.compactMap { material -> LibraryItem? in
                let keys = ([material.url] + material.savedURLs).map(SourceIndex.key)
                guard !keys.contains(where: preparedKeys.contains), let url = URL(string: material.url) else { return nil }
                let id = Self.linkID(material.url)
                return LibraryItem(
                    id: id,
                    kind: .link,
                    title: material.title,
                    source: SourceRef(name: source.name, homepage: URL(string: source.url)),
                    originalURL: url,
                    addedAt: addedAt[id],
                    excerpt: url.host(),
                    cover: nil,
                    progress: nil,
                    isRead: readings[id]?.isRead ?? false
                )
            }
        }
        return (prepared + bookItems + links).sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
    }
}

/// Finds the author, blog or channel a saved link came from.
private struct SourceIndex {
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

    func source(for url: String) -> SourceRef? {
        if let known = sources[Self.key(url)] { return known }
        guard let parsed = URL(string: url), let host = parsed.host() else { return nil }
        return SourceRef(name: Self.siteName(host), homepage: URL(string: "\(parsed.scheme ?? "https")://\(host)"))
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
        if let parsed = URL(string: url), let video = YouTube.videoID(in: parsed) { return "youtube:\(video)" }
        return url
    }
}

extension ImportPackage {
    var cover: Cover? {
        if material.kind == .video {
            return YouTube.videoID(in: material.sourceURL)
                .flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/hqdefault.jpg") }
                .map(Cover.remote)
        }
        guard let body, let path = ArticleBody.firstImagePath(body) else { return nil }
        return .articleFile(materialID: material.id, path: path)
    }
}
