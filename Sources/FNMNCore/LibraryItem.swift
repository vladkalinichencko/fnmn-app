import Foundation

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
    var declaredSource: SourceRef? {
        guard let source, let name = source.name else {
            return nil
        }
        return SourceRef(name: name, homepage: source.homepage)
    }

    var authors: SourceRef? {
        byline.map { SourceRef(name: $0, homepage: nil) }
    }
}

public enum Cover: Codable, Hashable, Sendable {
    case articleFile(materialID: String, path: String)
    case stored(materialID: String)
    case remote(URL)
}

public enum LibraryGrouping: String, CaseIterable, Hashable, Sendable {
    case albums, publishers, types, months
}

public enum GroupSort: String, CaseIterable, Hashable, Sendable {
    case standard, name, size, recent, opened
}

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
    public let title: String?
    public let items: [LibraryItem]
}

public struct AlbumSummary: Identifiable, Hashable, Sendable {
    public let grouping: LibraryGrouping
    public let key: String
    public let name: String
    public let count: Int
    public let front: [LibraryItem]
    public var id: String { Self.id(grouping, key) }

    public static func id(_ grouping: LibraryGrouping, _ key: String) -> String { "\(grouping.rawValue):\(key)" }
}

public struct AnnotationGroup: Identifiable, Sendable {
    public let item: LibraryItem
    public let annotations: [Annotation]
    public var id: String { item.id }
}
