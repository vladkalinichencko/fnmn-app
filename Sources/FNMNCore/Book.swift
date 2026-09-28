import Foundation

public struct BookTOCEntry: Codable, Equatable, Identifiable, Sendable {
    public let ordinal: Int
    public let level: Int
    public let title: String
    public var id: Int { ordinal }
}

public struct BookMetadata: Codable, Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let authors: [String]
    public let contributors: [String]?
    public let language: String
    public let sourceName: String
    public let schemaVersion: Int
    public let contentFile: String
    public let assetsDirectory: String
    public let toc: [BookTOCEntry]

    enum CodingKeys: String, CodingKey {
        case title, subtitle, authors, contributors, language, toc
        case sourceName = "source_name"
        case schemaVersion = "schema_version"
        case contentFile = "content_file"
        case assetsDirectory = "assets_directory"
    }
}

public struct BookValidation: Codable, Equatable, Sendable {
    public let headings: Int
    public let images: Int
    public let errors: [String]
}

public struct BookRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let metadata: BookMetadata
    public let directoryName: String

    public init(metadata: BookMetadata) {
        id = "book:\(metadata.sourceName)"
        self.metadata = metadata
        directoryName = BookCatalog.storageName(for: id)
    }
}

public struct BookImport: Equatable, Sendable {
    public let record: BookRecord
    public let validation: BookValidation
    public let imagePaths: [String]
    public let footnoteIDs: [String]
}

public enum BookError: Error, Equatable {
    case missing(String)
    case rejected([String])
    case unsupportedSchema(Int)
}

public enum BookCatalog {
    public static func inspect(from directory: URL) throws -> BookImport {
        let metadata = try decoder.decode(BookMetadata.self, from: try data("metadata.json", in: directory))
        guard metadata.schemaVersion == 1 else { throw BookError.unsupportedSchema(metadata.schemaVersion) }
        let validation = try decoder.decode(BookValidation.self, from: try data("validation.json", in: directory))
        guard validation.errors.isEmpty else { throw BookError.rejected(validation.errors) }
        let content = try String(contentsOf: file(metadata.contentFile, in: directory), encoding: .utf8)
        let imagePaths = images(in: content)
        for path in imagePaths {
            _ = try file(path, in: directory)
        }
        let footnoteIDs = footnotes(in: content)
        return BookImport(
            record: BookRecord(metadata: metadata),
            validation: validation,
            imagePaths: imagePaths,
            footnoteIDs: footnoteIDs
        )
    }

    public static func headingID(in position: ReadingPosition) -> Int? {
        guard position.blockID.hasPrefix("toc:") else { return nil }
        return Int(position.blockID.dropFirst(4))
    }

    static func storageName(for id: String) -> String {
        Data(id.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let decoder = JSONDecoder()

    private static func data(_ name: String, in directory: URL) throws -> Data {
        try Data(contentsOf: file(name, in: directory))
    }

    private static func file(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appending(path: name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw BookError.missing(name) }
        return url
    }

    private static func images(in markdown: String) -> [String] {
        markdown.matches(of: /!\[[^\]]*\]\(([^)]+)\)/).map { String($0.1) }
    }

    private static func footnotes(in markdown: String) -> [String] {
        Array(Set(markdown.matches(of: /\[\^([^\]]+)\](?!:)/).map { String($0.1) })).sorted()
    }
}
