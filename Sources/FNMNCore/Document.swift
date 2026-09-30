import Foundation

public struct BrowserCatalog: Codable, Equatable, Sendable {
    public let collections: [Collection]
    public let sources: [Source]

    public struct Collection: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
    }

    public struct Source: Codable, Equatable, Sendable {
        public let name: String
        public let url: String
        public let kind: String
        public let savedIn: [String]
        public let foundIn: [String]
        public let materials: [SavedMaterial]

        enum CodingKeys: String, CodingKey {
            case name, url, kind, materials
            case savedIn = "saved_in"
            case foundIn = "found_in"
        }
    }

    public struct SavedMaterial: Codable, Equatable, Sendable {
        public let title: String
        public let url: String
        public let savedURLs: [String]
        public let savedIn: [String]
        public let foundIn: [String]

        enum CodingKeys: String, CodingKey {
            case title, url
            case savedURLs = "saved_urls"
            case savedIn = "saved_in"
            case foundIn = "found_in"
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            title = try values.decode(String.self, forKey: .title)
            url = try values.decode(String.self, forKey: .url)
            savedURLs = try values.decodeIfPresent([String].self, forKey: .savedURLs) ?? []
            savedIn = try values.decode([String].self, forKey: .savedIn)
            foundIn = try values.decode([String].self, forKey: .foundIn)
        }
    }
}

public struct ImportPackage: Codable, Equatable, Sendable {
    public let version: Int
    public let material: Material
    public let sections: [Section]
    public let blocks: [Block]
    public let folders: [String]
    public let body: String?

    public init(version: Int = 1, material: Material, sections: [Section], blocks: [Block], folders: [String] = [], body: String? = nil) {
        self.version = version
        self.material = material
        self.sections = sections
        self.blocks = blocks
        self.folders = folders
        self.body = body
    }
}

public struct Material: Codable, Equatable, Identifiable, Sendable {
    /// `link` is a page nothing could be made of: it has no text, and opening it opens the page.
    public enum Kind: String, Codable, Sendable { case article, video, book, link }
    public let id: String
    public let kind: Kind
    public let title: String
    /// The page the material was made from; a material made from a file has none, and its original is that
    /// file, kept in `originals/`.
    public let sourceURL: URL?
    public let byline: String?

    public init(id: String, kind: Kind, title: String, sourceURL: URL?, byline: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sourceURL = sourceURL
        self.byline = byline
    }
}

public struct Section: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let parentID: String?
    public let title: String
    public let level: Int
    public let firstBlockID: String

    public init(id: String, parentID: String?, title: String, level: Int, firstBlockID: String) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.level = level
        self.firstBlockID = firstBlockID
    }
}

public struct Block: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case heading, paragraph, image, formula, video, transcript }
    public let id: String
    public let sectionID: String?
    public let kind: Kind
    public let html: String
    public let sourceFragment: String?
    public let mediaURL: URL?
    public let startSeconds: Double?

    public init(id: String, sectionID: String?, kind: Kind, html: String, sourceFragment: String? = nil, mediaURL: URL? = nil, startSeconds: Double? = nil) {
        self.id = id
        self.sectionID = sectionID
        self.kind = kind
        self.html = html
        self.sourceFragment = sourceFragment
        self.mediaURL = mediaURL
        self.startSeconds = startSeconds
    }
}

public struct ReadingPosition: Codable, Equatable, Sendable {
    public let blockID: String
    public let textOffset: Int
    public let videoSeconds: Double?

    public init(blockID: String, textOffset: Int = 0, videoSeconds: Double? = nil) {
        self.blockID = blockID
        self.textOffset = textOffset
        self.videoSeconds = videoSeconds
    }
}

public struct MaterialReading: Codable, Equatable, Sendable {
    public var openedAt: Date?
    public var isRead: Bool
    public var progress: Double?

    public init(openedAt: Date? = nil, isRead: Bool = false, progress: Double? = nil) {
        self.openedAt = openedAt
        self.isRead = isRead
        self.progress = progress
    }
}

extension ReadingPosition {
    public static func piece(_ index: Int) -> ReadingPosition {
        ReadingPosition(blockID: "piece:\(index)")
    }

    public var pieceIndex: Int? {
        guard blockID.hasPrefix("piece:") else { return nil }
        return Int(blockID.dropFirst(6))
    }
}
