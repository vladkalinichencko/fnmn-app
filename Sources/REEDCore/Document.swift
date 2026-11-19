import CryptoKit
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

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            url = try values.decode(String.self, forKey: .url)
            kind = try values.decode(String.self, forKey: .kind)
            savedIn = try values.decodeIfPresent([String].self, forKey: .savedIn) ?? []
            foundIn = try values.decodeIfPresent([String].self, forKey: .foundIn) ?? []
            materials = try values.decode([SavedMaterial].self, forKey: .materials)
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
            savedIn = try values.decodeIfPresent([String].self, forKey: .savedIn) ?? []
            foundIn = try values.decodeIfPresent([String].self, forKey: .foundIn) ?? []
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

extension ImportPackage {
    public static func link(_ url: URL) -> ImportPackage {
        let path = ((url.host() ?? "") + url.path(percentEncoded: true))
        let title = path.hasSuffix("/") ? String(path.dropLast()) : path
        return ImportPackage(
            material: Material(id: "link:\(url.absoluteString)", kind: .link, title: title.isEmpty ? url.absoluteString : title, sourceURL: url),
            sections: [], blocks: []
        )
    }

    public static func file(_ file: URL) throws -> ImportPackage {
        let name = file.deletingPathExtension().lastPathComponent
        return ImportPackage(
            material: Material(id: try fileID(file), kind: .link, title: name.isEmpty ? file.lastPathComponent : name, sourceURL: nil),
            sections: [], blocks: []
        )
    }

    static func fileID(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return "file:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct Material: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case article, video, book, link }
    public let id: String
    public let kind: Kind
    public let title: String
    public let sourceURL: URL?
    public let byline: String?
    public let source: PageSource?

    public init(id: String, kind: Kind, title: String, sourceURL: URL?, byline: String? = nil, source: PageSource? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sourceURL = sourceURL
        self.byline = byline
        self.source = source
    }
}

public struct PageSource: Codable, Equatable, Sendable {
    public let name: String?
    public let homepage: URL

    public init(name: String?, homepage: URL) {
        self.name = name
        self.homepage = homepage
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
