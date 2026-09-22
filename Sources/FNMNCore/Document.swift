import Foundation

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
    public enum Kind: String, Codable, Sendable { case article, video }
    public let id: String
    public let kind: Kind
    public let title: String
    public let sourceURL: URL
    public let byline: String?

    public init(id: String, kind: Kind, title: String, sourceURL: URL, byline: String? = nil) {
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

    public init(openedAt: Date? = nil, isRead: Bool = false) {
        self.openedAt = openedAt
        self.isRead = isRead
    }
}

public struct Note: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let materialID: String
    public let blockID: String?
    public var text: String

    public init(id: UUID = UUID(), materialID: String, blockID: String?, text: String) {
        self.id = id
        self.materialID = materialID
        self.blockID = blockID
        self.text = text
    }
}
