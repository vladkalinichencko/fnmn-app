import Foundation

/// Everything the library knows except reading progress and the texts of articles, which stay on disk.
/// Only `applying(_:)` and the importers change it.
public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var articles: [ArticleEntry] = []
    public var browserCatalog: BrowserCatalog?
    public var albums: [String] = []
    public var placements: [String: [String]] = [:]
    public var annotations: [Annotation] = []
    public var archived: [String] = []
    public var addedAt: [String: Date] = [:]
    public var articleRevisions: [String: String] = [:]
    /// When each material was deleted, so its delivery, which stays in the FNMN folder, is not taken in again.
    public var deletedAt: [String: Date] = [:]

    public init() {}

    public func isArchived(_ materialID: String) -> Bool {
        archived.contains(materialID)
    }

    public func albums(of materialID: String) -> [String] {
        placements[materialID] ?? []
    }

    /// The material that stands for a page: the one made from it, or else its link.
    public func materialID(forPage url: URL) -> String? {
        let key = SourceIndex.key(url)
        let samePage = articles.filter { $0.material.sourceURL.map(SourceIndex.key) == key }
        return (samePage.first { $0.material.kind != .link } ?? samePage.first)?.material.id
    }

    /// The source of one material without building every tile, for the reader's header.
    public func source(of itemID: String) -> SourceRef? {
        guard let article = articles.first(where: { $0.material.id == itemID }) else {
            return nil
        }
        guard let sourceURL = article.material.sourceURL else {
            return article.material.authors
        }
        var index = SourceIndex(catalog: browserCatalog, declared: articles.compactMap(\.material.source))
        return index.source(for: sourceURL)
    }

    /// Adds or replaces a prepared article or video. A material that is in no album yet lands in the albums
    /// the package names; otherwise the reader's albums stay. A changed text drops the old marks.
    public mutating func importPackage(_ package: ImportPackage, at date: Date, delivery: String? = nil, deliveredAt: Date? = nil) throws {
        guard package.version == 1 else { throw LibraryError.unsupportedVersion(package.version) }
        let hasBody = !(package.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasBody || !package.blocks.isEmpty || package.material.kind == .link else { throw LibraryError.emptyDocument }
        let id = package.material.id
        if try !replaceLinks(to: package.material) { return }
        deletedAt[id] = nil
        let entry = ArticleEntry(package, delivery: delivery, deliveredAt: deliveredAt)
        if let index = articles.firstIndex(where: { $0.material.id == id }) {
            if articles[index].textDigest != entry.textDigest {
                // Marks another device made on the new text after it rewrote the delivery may have arrived first.
                forgetMarks(of: id, before: deliveredAt)
            }
            articles[index] = entry
        } else {
            articles.append(entry)
            addedAt[id] = addedAt[id] ?? date
        }
        if albums(of: id).isEmpty {
            place(id, in: package.folders)
        }
    }

    /// A link and the material later made from the same page are one thing in the library: the material takes
    /// the link's place, with its albums and archive state, and a link that arrives after it is dropped.
    /// Returns whether the incoming material should enter the library.
    private mutating func replaceLinks(to material: Material) throws -> Bool {
        guard let key = material.sourceURL.map(SourceIndex.key) else { return true }
        let samePage = articles.filter { $0.material.id != material.id && $0.material.sourceURL.map(SourceIndex.key) == key }
        if material.kind == .link { return !samePage.contains { $0.material.kind != .link } }
        for link in samePage where link.material.kind == .link {
            let linkID = link.material.id
            place(material.id, in: albums(of: linkID))
            if isArchived(linkID), !isArchived(material.id) { archived.append(material.id) }
            if addedAt[material.id] == nil { addedAt[material.id] = addedAt[linkID] }
            self = try applying(.delete(itemID: linkID))
        }
        return true
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

    mutating func forgetMarks(of materialID: String, before date: Date? = nil) {
        annotations.removeAll { annotation in
            guard annotation.materialID == materialID else { return false }
            guard let date, let updatedAt = annotation.updatedAt else { return true }
            return updatedAt < date
        }
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
        case let .albumNameTaken(name): "A collection named “\(name)” already exists."
        case .emptyAlbumName: "Enter a collection name."
        case .cloudFolderMissing: "This material lives in the FNMN folder in iCloud Drive. Choose that folder again with + → File."
        }
    }
}

