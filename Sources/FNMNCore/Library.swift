import Foundation

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var packages: [ImportPackage] = []
    public var books: [BookRecord] = []
    public var positions: [String: ReadingPosition] = [:]
    public var readings: [String: MaterialReading] = [:]
    public var notes: [Note] = []
    public var folders: [String] = []
    public var placements: [String: [String]] = [:]
    public var highlights: [Highlight] = []
    public var archived: [String] = []

    public init() {}

    public var continuedID: String? {
        let known = Set(packages.map(\.material.id) + books.map(\.id))
        let opened = readings.compactMap { materialID, reading -> (String, Date)? in
            guard let openedAt = reading.openedAt, known.contains(materialID), !archived.contains(materialID) else { return nil }
            return (materialID, openedAt)
        }
        if let materialID = opened.max(by: { $0.1 < $1.1 })?.0 { return materialID }
        if let article = packages.first(where: { positions[$0.material.id] != nil }) {
            return article.material.id
        }
        return books.first(where: { positions[$0.id] != nil })?.id
    }

    public var continuedPackage: ImportPackage? {
        packages.first { $0.material.id == continuedID }
    }

    public mutating func importBook(_ record: BookRecord) {
        if let index = books.firstIndex(where: { $0.id == record.id }) {
            books[index] = record
        } else {
            books.append(record)
        }
    }

    public mutating func recordOpening(materialID: String, at date: Date) {
        readings[materialID, default: MaterialReading()].openedAt = date
    }

    public mutating func setRead(_ isRead: Bool, materialID: String) {
        readings[materialID, default: MaterialReading()].isRead = isRead
    }

    public mutating func setProgress(_ progress: Double, materialID: String) {
        readings[materialID, default: MaterialReading()].progress = progress
    }

    public mutating func setArchived(_ isArchived: Bool, materialID: String) {
        if isArchived {
            if !archived.contains(materialID) { archived.append(materialID) }
        } else {
            archived.removeAll { $0 == materialID }
        }
    }

    public func isArchived(_ materialID: String) -> Bool {
        archived.contains(materialID)
    }

    public func folderNames(for materialID: String) -> [String] {
        if let names = placements[materialID] { return names }
        return packages.first { $0.material.id == materialID }?.folders ?? []
    }

    public func packages(in folder: String) -> [ImportPackage] {
        packages.filter { folderNames(for: $0.material.id).contains(folder) }
    }

    public func books(in folder: String) -> [BookRecord] {
        books.filter { folderNames(for: $0.id).contains(folder) }
    }

    public func matchingPackages(_ query: String) -> [ImportPackage] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return packages }
        return packages.filter { $0.matches(needle) }
    }

    public func matchingBooks(_ query: String) -> [BookRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return books }
        return books.filter { book in
            book.matches(needle) || folderNames(for: book.id).contains { $0.localizedStandardContains(needle) }
        }
    }

    public mutating func importPackage(_ package: ImportPackage) throws {
        guard package.version == 1 else { throw LibraryError.unsupportedVersion(package.version) }
        guard !package.blocks.isEmpty else { throw LibraryError.emptyDocument }
        let prior = folderNames(for: package.material.id)
        let merged = Array(Set(prior + package.folders)).sorted()
        let stored = ImportPackage(material: package.material, sections: package.sections, blocks: package.blocks, folders: merged, body: package.body)
        if let index = packages.firstIndex(where: { $0.material.id == package.material.id }) {
            packages[index] = stored
        } else {
            packages.append(stored)
        }
        placements[package.material.id] = merged
        folders = Array(Set(folders + merged)).sorted()
    }

    public mutating func assign(materialID: String, to folders: [String]) {
        let names = Array(Set(folders.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        placements[materialID] = names
        self.folders = Array(Set(self.folders + names)).sorted()
        writePackageFolders(materialID, names)
    }

    public mutating func place(materialID: String, in folder: String) {
        var names = folderNames(for: materialID)
        if !names.contains(folder) { names.append(folder) }
        names.sort()
        placements[materialID] = names
        folders = Array(Set(folders + [folder])).sorted()
        writePackageFolders(materialID, names)
    }

    public mutating func move(materialID: String, to folder: String) {
        place(materialID: materialID, in: folder)
    }

    public mutating func renameFolder(from name: String, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard folders.contains(name) else { return false }
        if trimmed == name { return true }
        guard !trimmed.isEmpty, !folders.contains(trimmed) else { return false }
        let ids = Set(placements.keys).union(packages.map(\.material.id)).union(books.map(\.id))
        for id in ids {
            var names = folderNames(for: id)
            guard names.contains(name) else { continue }
            names = Array(Set(names.map { $0 == name ? trimmed : $0 })).sorted()
            placements[id] = names
            writePackageFolders(id, names)
        }
        folders = Array(Set(folders.map { $0 == name ? trimmed : $0 })).sorted()
        return true
    }

    public mutating func adoptPackageFolders() {
        for package in packages where placements[package.material.id] == nil && !package.folders.isEmpty {
            placements[package.material.id] = package.folders.sorted()
            folders = Array(Set(folders + package.folders)).sorted()
        }
    }

    private mutating func writePackageFolders(_ materialID: String, _ names: [String]) {
        guard let index = packages.firstIndex(where: { $0.material.id == materialID }) else { return }
        let package = packages[index]
        packages[index] = ImportPackage(material: package.material, sections: package.sections, blocks: package.blocks, folders: names, body: package.body)
    }

    public mutating func recordVideoTime(materialID: String, blockID: String, seconds: Double) -> Bool {
        if let current = positions[materialID], current.blockID != blockID {
            return false
        }
        positions[materialID] = ReadingPosition(blockID: blockID, videoSeconds: seconds)
        return true
    }
}

public enum LibraryError: Error, Equatable {
    case unsupportedVersion(Int)
    case emptyDocument
    case escapedPath
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

public actor LibraryFile {
    private struct UserState: Codable {
        var positions: [String: ReadingPosition]
        var notes: [Note]
        var folders: [String]
        var readings: [String: MaterialReading]
        var books: [BookRecord]
        var placements: [String: [String]]
        var highlights: [Highlight]
        var archived: [String]

        init(
            positions: [String: ReadingPosition],
            notes: [Note],
            folders: [String],
            readings: [String: MaterialReading],
            books: [BookRecord],
            placements: [String: [String]],
            highlights: [Highlight],
            archived: [String]
        ) {
            self.positions = positions
            self.notes = notes
            self.folders = folders
            self.readings = readings
            self.books = books
            self.placements = placements
            self.highlights = highlights
            self.archived = archived
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            positions = try container.decode([String: ReadingPosition].self, forKey: .positions)
            notes = try container.decode([Note].self, forKey: .notes)
            folders = try container.decode([String].self, forKey: .folders)
            readings = try container.decodeIfPresent([String: MaterialReading].self, forKey: .readings) ?? [:]
            books = try container.decodeIfPresent([BookRecord].self, forKey: .books) ?? []
            placements = try container.decodeIfPresent([String: [String]].self, forKey: .placements) ?? [:]
            highlights = try container.decodeIfPresent([Highlight].self, forKey: .highlights) ?? []
            archived = try container.decodeIfPresent([String].self, forKey: .archived) ?? []
        }
    }

    public nonisolated let root: URL
    private var directory: URL { root }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) {
        root = url
    }

    public func load() throws -> LibrarySnapshot {
        var snapshot = LibrarySnapshot()
        let packagesDirectory = directory.appending(path: "packages")
        if let files = try? FileManager.default.contentsOfDirectory(at: packagesDirectory, includingPropertiesForKeys: nil) {
            snapshot.packages = try files.filter { $0.pathExtension == "json" }.map { try decoder.decode(ImportPackage.self, from: Data(contentsOf: $0)) }
        }
        let stateURL = directory.appending(path: "state.json")
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let state = try decoder.decode(UserState.self, from: Data(contentsOf: stateURL))
            snapshot.positions = state.positions
            snapshot.notes = state.notes
            snapshot.folders = state.folders
            snapshot.readings = state.readings
            snapshot.books = state.books
            snapshot.placements = state.placements
            snapshot.highlights = state.highlights
            snapshot.archived = state.archived
        }
        snapshot.adoptPackageFolders()
        return snapshot
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        let packagesDirectory = directory.appending(path: "packages")
        try FileManager.default.createDirectory(at: packagesDirectory, withIntermediateDirectories: true)
        for package in snapshot.packages {
            let name = package.material.id.data(using: .utf8)!.base64EncodedString().replacingOccurrences(of: "/", with: "_")
            try encoder.encode(package).write(to: packagesDirectory.appending(path: "\(name).json"), options: .atomic)
        }
        try saveState(snapshot)
    }

    public func copyBook(from source: URL, named directoryName: String) throws {
        let books = directory.appending(path: "books")
        try FileManager.default.createDirectory(at: books, withIntermediateDirectories: true)
        let destination = books.appending(path: directoryName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func removeBook(named directoryName: String) throws {
        let destination = directory.appending(path: "books").appending(path: directoryName)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    public func installRuntime(from bundle: URL) throws {
        let destination = directory.appending(path: "runtime")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: bundle, to: destination)
    }

    public func saveState(_ snapshot: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = UserState(
            positions: snapshot.positions,
            notes: snapshot.notes,
            folders: snapshot.folders,
            readings: snapshot.readings,
            books: snapshot.books,
            placements: snapshot.placements,
            highlights: snapshot.highlights,
            archived: snapshot.archived
        )
        try encoder.encode(state).write(to: directory.appending(path: "state.json"), options: .atomic)
    }

    public func bookText(directoryName: String, contentFile: String) throws -> String {
        guard let url = Self.bookFile(root: directory, directoryName: directoryName, path: contentFile) else {
            throw LibraryError.escapedPath
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static func bookFile(root: URL, directoryName: String, path: String) -> URL? {
        guard !directoryName.isEmpty, !directoryName.hasPrefix("/"), !directoryName.contains(".."), !directoryName.contains("/") else { return nil }
        let folder = root.appending(path: "books").appending(path: directoryName).standardizedFileURL
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("..") else { return nil }
        let destination = folder.appending(path: path).standardizedFileURL
        guard destination.path == folder.path || destination.path.hasPrefix(folder.path + "/") else { return nil }
        return destination
    }

    public static func articleFile(root: URL, materialID: String, path: String) -> URL? {
        let folder = articleDirectory(root: root, materialID: materialID).standardizedFileURL
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("..") else { return nil }
        let destination = folder.appending(path: path).standardizedFileURL
        guard destination.path == folder.path || destination.path.hasPrefix(folder.path + "/") else { return nil }
        return destination
    }

    public func saveArticleFiles(_ files: [String: Data], materialID: String) throws {
        let folder = Self.articleDirectory(root: directory, materialID: materialID)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        for (path, data) in files {
            guard let destination = Self.articleFile(root: directory, materialID: materialID, path: path) else {
                throw LibraryError.escapedPath
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
    }

    public func removeArticleFiles(materialID: String) throws {
        let folder = Self.articleDirectory(root: directory, materialID: materialID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    private static func articleDirectory(root: URL, materialID: String) -> URL {
        let name = Data(materialID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return root.appending(path: "articles").appending(path: name)
    }
}

extension ImportPackage {
    func matches(_ query: String) -> Bool {
        var fields = [material.title, material.sourceURL.absoluteString] + folders + sections.map(\.title)
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

public enum CaptureSource: String, Codable, Equatable, Sendable {
    case web, arxiv, youtube, x, substack, chatgpt, pdf

    public var folderName: String {
        switch self {
        case .web: "Web"
        case .arxiv: "arXiv"
        case .youtube: "YouTube"
        case .x: "X"
        case .substack: "Substack"
        case .chatgpt: "ChatGPT"
        case .pdf: "PDF"
        }
    }
}

public enum CaptureRoute {
    public static func source(for url: URL) -> CaptureSource? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        let host = url.host?.lowercased() ?? ""
        guard !host.isEmpty else { return nil }
        if host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") { return .youtube }
        if host == "arxiv.org" || host.hasSuffix(".arxiv.org") { return .arxiv }
        if host == "x.com" || host.hasSuffix(".x.com") || host == "twitter.com" || host.hasSuffix(".twitter.com") { return .x }
        if host == "substack.com" || host.hasSuffix(".substack.com") { return .substack }
        if host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") || host == "chat.openai.com" { return .chatgpt }
        if url.pathExtension.lowercased() == "pdf" { return .pdf }
        return .web
    }
}

public enum CaptureError: Error, Equatable {
    case unprepared(CaptureSource)
    case unrecognizedDocument
}

extension CaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unprepared(source): "\(source.folderName) is recognized, but the Mac service does not prepare it yet."
        case .unrecognizedDocument: "Choose an article package, a book folder, or a PDF."
        }
    }
}
