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
