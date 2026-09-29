import Foundation

/// Everything the library knows except reading progress and the texts of articles, which stay on disk.
/// Only `applying(_:)` and the importers change it.
public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var articles: [ArticleEntry] = []
    public var books: [BookRecord] = []
    public var browserCatalog: BrowserCatalog?
    public var albums: [String] = []
    public var placements: [String: [String]] = [:]
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

    /// Adds or replaces a prepared article or video. A material that is in no album yet lands in the albums
    /// the package names; otherwise the reader's albums stay. A changed text drops the old marks.
    public mutating func importPackage(_ package: ImportPackage, at date: Date, delivery: String? = nil) throws {
        guard package.version == 1 else { throw LibraryError.unsupportedVersion(package.version) }
        let hasBody = !(package.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasBody || !package.blocks.isEmpty else { throw LibraryError.emptyDocument }
        let id = package.material.id
        let entry = ArticleEntry(package, delivery: delivery)
        if let index = articles.firstIndex(where: { $0.material.id == id }) {
            if articles[index].textDigest != entry.textDigest {
                forgetMarks(of: id)
            }
            articles[index] = entry
        } else {
            articles.append(entry)
            addedAt[id] = date
        }
        if albums(of: id).isEmpty {
            place(id, in: package.folders)
        }
    }

    public mutating func importBook(_ record: BookRecord, at date: Date) {
        if let index = books.firstIndex(where: { $0.id == record.id }) {
            if books[index] != record { forgetMarks(of: record.id) }
            books[index] = record
        } else {
            books.append(record)
            addedAt[record.id] = date
        }
    }

    /// Saved links without a prepared material go into their albums (address → album names);
    /// a link the reader already put somewhere stays there.
    mutating func placeLinks(_ albums: [String: [String]]) {
        for item in items where item.kind == .link && self.albums(of: item.id).isEmpty {
            if let names = albums[String(item.id.dropFirst("link:".count))] {
                place(item.id, in: names)
            }
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

    mutating func forgetMarks(of materialID: String) {
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
    case cloudFolderMissing
}

extension LibraryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version): "Unsupported package version \(version)."
        case .emptyDocument: "The document has no text."
        case .escapedPath: "A file path points outside the library."
        case let .albumNameTaken(name): "An album named “\(name)” already exists."
        case .emptyAlbumName: "Enter an album name."
        case .cloudFolderMissing: "This material lives in the FNMN folder in iCloud Drive. Choose that folder again with + → File."
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

extension BookRecord {
    func matches(_ query: String) -> Bool {
        var fields = [metadata.title, metadata.sourceName] + metadata.authors + metadata.toc.map(\.title)
        if let subtitle = metadata.subtitle { fields.append(subtitle) }
        if let contributors = metadata.contributors { fields.append(contentsOf: contributors) }
        return fields.contains { $0.localizedStandardContains(query) }
    }
}
