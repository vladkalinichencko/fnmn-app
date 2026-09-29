import Foundation

/// Everything the library knows. Only `applying(_:)` and the importers change it.
public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var packages: [ImportPackage] = []
    public var books: [BookRecord] = []
    public var browserCatalog: BrowserCatalog?
    public var albums: [String] = []
    public var placements: [String: [String]] = [:]
    public var positions: [String: ReadingPosition] = [:]
    public var readThrough: [String: Int] = [:]
    public var readings: [String: MaterialReading] = [:]
    public var annotations: [Annotation] = []
    public var archived: [String] = []
    public var addedAt: [String: Date] = [:]
    public var articleRevisions: [String: String] = [:]
    /// Videos saved on the device for the system player: item id → file name in `videos/`.
    public var videoFiles: [String: String] = [:]

    public init() {}

    public func isArchived(_ materialID: String) -> Bool {
        archived.contains(materialID)
    }

    public func albums(of materialID: String) -> [String] {
        placements[materialID] ?? []
    }

    public var continuedID: String? {
        let known = Set(packages.map(\.material.id) + books.map(\.id))
        let opened = readings.compactMap { materialID, reading -> (String, Date)? in
            guard let openedAt = reading.openedAt, known.contains(materialID), !isArchived(materialID) else { return nil }
            return (materialID, openedAt)
        }
        if let materialID = opened.max(by: { $0.1 < $1.1 })?.0 { return materialID }
        if let article = packages.first(where: { positions[$0.material.id] != nil }) {
            return article.material.id
        }
        return books.first(where: { positions[$0.id] != nil })?.id
    }

    /// Adds or replaces a prepared article or video. A material that is in no album yet lands in the albums
    /// the package names; otherwise the reader's albums stay. A changed text drops the old place and marks.
    public mutating func importPackage(_ package: ImportPackage, at date: Date) throws {
        guard package.version == 1 else { throw LibraryError.unsupportedVersion(package.version) }
        let hasBody = !(package.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasBody || !package.blocks.isEmpty else { throw LibraryError.emptyDocument }
        let id = package.material.id
        if let index = packages.firstIndex(where: { $0.material.id == id }) {
            let existing = packages[index]
            if existing.body != package.body || existing.blocks != package.blocks {
                forgetReading(of: id)
            }
            packages[index] = package
        } else {
            packages.append(package)
            addedAt[id] = date
        }
        if albums(of: id).isEmpty {
            place(id, in: package.folders)
        }
    }

    public mutating func importBook(_ record: BookRecord, at date: Date) {
        if let index = books.firstIndex(where: { $0.id == record.id }) {
            books[index] = record
            forgetReading(of: record.id)
        } else {
            books.append(record)
            addedAt[record.id] = date
        }
    }

    mutating func place(_ materialID: String, in names: [String]) {
        let names = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        placements[materialID] = Self.ordered(albums(of: materialID) + names)
        albums = Self.ordered(albums + names)
    }

    /// Albums that were named after browser collections give way to the reviewed albums of a new browser import.
    mutating func retireAlbums(_ names: [String]) {
        albums.removeAll(where: names.contains)
        placements = placements.compactMapValues { current in
            let rest = current.filter { !names.contains($0) }
            return rest.isEmpty ? nil : rest
        }
    }

    mutating func forgetReading(of materialID: String) {
        positions[materialID] = nil
        readThrough[materialID] = nil
        annotations.removeAll { $0.materialID == materialID }
    }

    static func ordered(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}

public enum LibraryError: Error, Equatable {
    case unsupportedVersion(Int)
    case emptyDocument
    case escapedPath
    case albumNameTaken(String)
    case emptyAlbumName
}

extension LibraryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version): "Unsupported package version \(version)."
        case .emptyDocument: "The document has no text."
        case .escapedPath: "A file path points outside the library."
        case let .albumNameTaken(name): "An album named “\(name)” already exists."
        case .emptyAlbumName: "Enter an album name."
        }
    }
}

extension BookError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .missing(name): "Missing \(name)"
        case let .rejected(errors): errors.joined(separator: ", ")
        case let .unsupportedSchema(version): "Unsupported book schema \(version)"
        }
    }
}

extension ImportPackage {
    func matches(_ query: String) -> Bool {
        let markdown = ArticleBody.readingMarkdown(body: body, blocks: blocks)
        var fields = [material.title, material.sourceURL.absoluteString] + sections.map(\.title)
        fields.append(contentsOf: ArticleBody.headings(in: markdown).map(\.title))
        if let byline = material.byline { fields.append(byline) }
        return fields.contains { $0.localizedStandardContains(query) }
    }
}

extension BookRecord {
    func matches(_ query: String) -> Bool {
        var fields = [metadata.title, metadata.sourceName] + metadata.authors + metadata.toc.map(\.title)
        if let subtitle = metadata.subtitle { fields.append(subtitle) }
        if let contributors = metadata.contributors { fields.append(contentsOf: contributors) }
        return fields.contains { $0.localizedStandardContains(query) }
    }
}
