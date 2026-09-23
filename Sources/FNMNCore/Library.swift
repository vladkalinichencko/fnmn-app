import Foundation

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var packages: [ImportPackage] = []
    public var books: [BookRecord] = []
    public var positions: [String: ReadingPosition] = [:]
    public var readings: [String: MaterialReading] = [:]
    public var folders: [String] = []
    public var placements: [String: [String]] = [:]
    public var highlights: [Highlight] = []
    public var archived: [String] = []
    public var articleRevisions: [String: String] = [:]

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
        let replacing = books.contains { $0.id == record.id }
        if let index = books.firstIndex(where: { $0.id == record.id }) {
            books[index] = record
        } else {
            books.append(record)
        }
        if replacing {
            positions[record.id] = nil
            highlights.removeAll { $0.materialID == record.id }
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
        packages.filter { folderNames(for: $0.material.id).contains(folder) && !isArchived($0.material.id) }
    }

    public func books(in folder: String) -> [BookRecord] {
        books.filter { folderNames(for: $0.id).contains(folder) && !isArchived($0.id) }
    }

    public func matchingPackages(_ query: String) -> [ImportPackage] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return packages }
        return packages.filter {
            $0.matches(needle) || folderNames(for: $0.material.id).contains { $0.localizedStandardContains(needle) }
        }
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
        let hasBody = !(package.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasBody || !package.blocks.isEmpty else { throw LibraryError.emptyDocument }
        let prior = folderNames(for: package.material.id)
        let merged = Array(Set(prior + package.folders)).sorted()
        if let existing = packages.first(where: { $0.material.id == package.material.id }),
           existing.body != package.body || existing.blocks != package.blocks {
            positions[package.material.id] = nil
            highlights.removeAll { $0.materialID == package.material.id }
        }
        if let index = packages.firstIndex(where: { $0.material.id == package.material.id }) {
            packages[index] = package
        } else {
            packages.append(package)
        }
        placements[package.material.id] = merged
        folders = Array(Set(folders + merged)).sorted()
    }

    public mutating func assign(materialID: String, to folders: [String]) {
        let names = Array(Set(folders.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        placements[materialID] = names
        self.folders = Array(Set(self.folders + names)).sorted()
    }

    public mutating func place(materialID: String, in folder: String) {
        var names = folderNames(for: materialID)
        if !names.contains(folder) { names.append(folder) }
        names.sort()
        placements[materialID] = names
        folders = Array(Set(folders + [folder])).sorted()
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

private struct Note: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let materialID: String
    let blockID: String?
    var text: String
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
        var packages: [ImportPackage]?
        var articleRevisions: [String: String]
        var readPackageFiles = false

        enum CodingKeys: String, CodingKey {
            case positions, notes, folders, readings, books, placements, highlights, archived, packages, articleRevisions
        }

        init(
            positions: [String: ReadingPosition],
            folders: [String],
            readings: [String: MaterialReading],
            books: [BookRecord],
            placements: [String: [String]],
            highlights: [Highlight],
            archived: [String],
            packages: [ImportPackage],
            articleRevisions: [String: String]
        ) {
            self.positions = positions
            self.notes = []
            self.folders = folders
            self.readings = readings
            self.books = books
            self.placements = placements
            self.highlights = highlights
            self.archived = archived
            self.packages = packages
            self.articleRevisions = articleRevisions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            positions = try container.decode([String: ReadingPosition].self, forKey: .positions)
            notes = try container.decodeIfPresent([Note].self, forKey: .notes) ?? []
            folders = try container.decode([String].self, forKey: .folders)
            readings = try container.decodeIfPresent([String: MaterialReading].self, forKey: .readings) ?? [:]
            books = try container.decodeIfPresent([BookRecord].self, forKey: .books) ?? []
            placements = try container.decodeIfPresent([String: [String]].self, forKey: .placements) ?? [:]
            highlights = try container.decodeIfPresent([Highlight].self, forKey: .highlights) ?? []
            archived = try container.decodeIfPresent([String].self, forKey: .archived) ?? []
            packages = try container.decodeIfPresent([ImportPackage].self, forKey: .packages)
            articleRevisions = try container.decodeIfPresent([String: String].self, forKey: .articleRevisions) ?? [:]
            readPackageFiles = !container.contains(.packages)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(positions, forKey: .positions)
            try container.encode(folders, forKey: .folders)
            try container.encode(readings, forKey: .readings)
            try container.encode(books, forKey: .books)
            try container.encode(placements, forKey: .placements)
            try container.encode(highlights, forKey: .highlights)
            try container.encode(archived, forKey: .archived)
            try container.encode(packages ?? [], forKey: .packages)
            try container.encode(articleRevisions, forKey: .articleRevisions)
        }
    }

    public nonisolated let root: URL
    public private(set) var corruptPackageNames: [String] = []
    private var directory: URL { root }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) {
        root = url
    }

    public func load() throws -> LibrarySnapshot {
        try recoverReplacedDirectories(in: directory.appending(path: "books"))
        try recoverReplacedItem(named: "runtime")
        var snapshot = LibrarySnapshot()
        var stateIncludesPackages = false
        var legacyNotes: [Note] = []
        let stateURL = directory.appending(path: "state.json")
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let state = try decoder.decode(UserState.self, from: Data(contentsOf: stateURL))
            snapshot.positions = state.positions
            snapshot.folders = state.folders
            snapshot.readings = state.readings
            snapshot.books = state.books
            snapshot.placements = state.placements
            snapshot.highlights = state.highlights
            snapshot.archived = state.archived
            snapshot.articleRevisions = state.articleRevisions
            legacyNotes = state.notes
            stateIncludesPackages = !state.readPackageFiles
            if stateIncludesPackages {
                snapshot.packages = state.packages ?? []
            }
        }
        if stateIncludesPackages {
            corruptPackageNames = []
        } else {
            snapshot.packages = readLegacyPackages()
        }
        try sweepUnreferencedBooks(snapshot)
        try sweepArticleRevisions(snapshot)
        snapshot.adoptPackageFolders()
        let foldedNotes = absorbLegacyNotes(legacyNotes, into: &snapshot)
        let foldedPlaces = absorbLegacyArticlePositions(into: &snapshot)
        if foldedNotes || foldedPlaces {
            try saveState(snapshot)
        }
        return snapshot
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        try saveState(snapshot)
    }

    public func storeArticle(_ package: ImportPackage, files: [String: Data], into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        var next = snapshot
        try next.importPackage(package)
        guard !files.isEmpty else {
            try save(next)
            return next
        }
        let revision = UUID().uuidString
        do {
            try writeArticleRevision(files, materialID: package.material.id, revision: revision)
            next.articleRevisions[package.material.id] = revision
            try save(next)
            try sweepArticleRevisions(next)
            return next
        } catch {
            try? removeArticleRevision(materialID: package.material.id, revision: revision)
            throw error
        }
    }

    public func storeBook(_ record: BookRecord, from source: URL, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        let previousName = snapshot.books.first { $0.id == record.id }?.directoryName
        var next = snapshot
        next.importBook(record)
        let books = directory.appending(path: "books")
        try FileManager.default.createDirectory(at: books, withIntermediateDirectories: true)
        let destination = books.appending(path: record.directoryName)
        let incoming = destination.appendingPathExtension("incoming")
        if FileManager.default.fileExists(atPath: incoming.path) {
            try FileManager.default.removeItem(at: incoming)
        }
        do {
            try FileManager.default.copyItem(at: source, to: incoming)
        } catch {
            try? FileManager.default.removeItem(at: incoming)
            throw error
        }
        let hadLive = FileManager.default.fileExists(atPath: destination.path)
        do {
            try replaceDirectory(at: destination, with: incoming)
            try saveState(next)
            try discardRetired(destination)
            if let previousName, previousName != record.directoryName {
                try removeBook(named: previousName)
            }
            return next
        } catch {
            if hadLive {
                try? restoreRetired(destination)
            } else if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            if FileManager.default.fileExists(atPath: incoming.path) {
                try? FileManager.default.removeItem(at: incoming)
            }
            throw error
        }
    }

    public func copyBook(from source: URL, named directoryName: String) throws {
        let books = directory.appending(path: "books")
        try FileManager.default.createDirectory(at: books, withIntermediateDirectories: true)
        let destination = books.appending(path: directoryName)
        let incoming = destination.appendingPathExtension("incoming")
        if FileManager.default.fileExists(atPath: incoming.path) {
            try FileManager.default.removeItem(at: incoming)
        }
        try FileManager.default.copyItem(at: source, to: incoming)
        try replaceDirectory(at: destination, with: incoming)
        try discardRetired(destination)
    }

    public func removeBook(named directoryName: String) throws {
        let destination = directory.appending(path: "books").appending(path: directoryName)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    public func installRuntime(from bundle: URL) throws {
        let destination = directory.appending(path: "runtime")
        let incoming = destination.appendingPathExtension("incoming")
        if FileManager.default.fileExists(atPath: incoming.path) {
            try FileManager.default.removeItem(at: incoming)
        }
        try FileManager.default.copyItem(at: bundle, to: incoming)
        try replaceDirectory(at: destination, with: incoming)
        try discardRetired(destination)
    }

    public func saveState(_ snapshot: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = UserState(
            positions: snapshot.positions,
            folders: snapshot.folders,
            readings: snapshot.readings,
            books: snapshot.books,
            placements: snapshot.placements,
            highlights: snapshot.highlights,
            archived: snapshot.archived,
            packages: snapshot.packages,
            articleRevisions: snapshot.articleRevisions
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

    public static func articleFile(root: URL, materialID: String, path: String, revision: String? = nil) -> URL? {
        guard revision?.contains("/") != true, revision?.contains("..") != true else { return nil }
        var folder = articleDirectory(root: root, materialID: materialID)
        if let revision, !revision.isEmpty {
            folder = folder.appending(path: revision)
        }
        folder = folder.standardizedFileURL
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("..") else { return nil }
        let destination = folder.appending(path: path).standardizedFileURL
        guard destination.path == folder.path || destination.path.hasPrefix(folder.path + "/") else { return nil }
        return destination
    }

    private func writeArticleRevision(_ files: [String: Data], materialID: String, revision: String) throws {
        for (path, data) in files {
            guard let destination = Self.articleFile(root: directory, materialID: materialID, path: path, revision: revision) else {
                throw LibraryError.escapedPath
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
    }

    private func removeArticleRevision(materialID: String, revision: String) throws {
        let folder = Self.articleDirectory(root: directory, materialID: materialID).appending(path: revision)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    private func absorbLegacyNotes(_ notes: [Note], into snapshot: inout LibrarySnapshot) -> Bool {
        guard !notes.isEmpty else { return false }
        for note in notes where !snapshot.highlights.contains(where: { $0.id == note.id }) {
            let piece: Int
            if let blockID = note.blockID, blockID.hasPrefix("piece:"), let index = Int(blockID.dropFirst(6)) {
                piece = index
            } else {
                piece = 0
            }
            snapshot.highlights.append(
                Highlight(id: note.id, materialID: note.materialID, piece: piece, quote: "", caption: note.text, mark: nil)
            )
        }
        return true
    }

    private func absorbLegacyArticlePositions(into snapshot: inout LibrarySnapshot) -> Bool {
        var changed = false
        for (materialID, position) in snapshot.positions {
            guard let package = snapshot.packages.first(where: { $0.material.id == materialID }),
                  let piece = ArticleBody.legacyPiece(for: position, in: package) else { continue }
            snapshot.positions[materialID] = .piece(piece)
            changed = true
        }
        return changed
    }

    private func readLegacyPackages() -> [ImportPackage] {
        let packagesDirectory = directory.appending(path: "packages")
        guard let files = try? FileManager.default.contentsOfDirectory(at: packagesDirectory, includingPropertiesForKeys: nil) else {
            corruptPackageNames = []
            return []
        }
        var packages: [ImportPackage] = []
        var corrupt: [String] = []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                packages.append(try decoder.decode(ImportPackage.self, from: Data(contentsOf: file)))
            } catch {
                corrupt.append(file.lastPathComponent)
            }
        }
        corruptPackageNames = corrupt
        return packages
    }

    private func sweepUnreferencedBooks(_ snapshot: LibrarySnapshot) throws {
        let books = directory.appending(path: "books")
        guard let children = try? FileManager.default.contentsOfDirectory(at: books, includingPropertiesForKeys: nil) else { return }
        let referenced = Set(snapshot.books.map(\.directoryName))
        for child in children {
            let name = child.lastPathComponent
            if name.hasSuffix(".incoming") || name.hasSuffix(".retired") { continue }
            if !referenced.contains(name) {
                try FileManager.default.removeItem(at: child)
            }
        }
    }

    private func sweepArticleRevisions(_ snapshot: LibrarySnapshot) throws {
        let articles = directory.appending(path: "articles")
        guard let keys = try? FileManager.default.contentsOfDirectory(at: articles, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let live = Dictionary(uniqueKeysWithValues: snapshot.articleRevisions.map {
            (Self.articleDirectory(root: directory, materialID: $0.key).lastPathComponent, $0.value)
        })
        for keyURL in keys {
            let revision = live[keyURL.lastPathComponent]
            guard let children = try? FileManager.default.contentsOfDirectory(at: keyURL, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                if let revision {
                    if child.lastPathComponent != revision {
                        try FileManager.default.removeItem(at: child)
                    }
                } else if UUID(uuidString: child.lastPathComponent) != nil {
                    try FileManager.default.removeItem(at: child)
                }
            }
        }
    }

    private func recoverReplacedDirectories(in folder: URL) throws {
        guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for item in children where item.pathExtension == "retired" {
            try finishReplacement(of: item.deletingPathExtension())
        }
        for item in children where item.pathExtension == "incoming" {
            try FileManager.default.removeItem(at: item)
        }
    }

    private func recoverReplacedItem(named name: String) throws {
        try finishReplacement(of: directory.appending(path: name))
        let incoming = directory.appending(path: name).appendingPathExtension("incoming")
        if FileManager.default.fileExists(atPath: incoming.path) {
            try FileManager.default.removeItem(at: incoming)
        }
    }

    private func finishReplacement(of destination: URL) throws {
        let retired = destination.appendingPathExtension("retired")
        guard FileManager.default.fileExists(atPath: retired.path) else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: retired)
        } else {
            try FileManager.default.moveItem(at: retired, to: destination)
        }
    }

    private func replaceDirectory(at destination: URL, with incoming: URL) throws {
        let retired = destination.appendingPathExtension("retired")
        if FileManager.default.fileExists(atPath: retired.path) {
            try FileManager.default.removeItem(at: retired)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: destination, to: retired)
        }
        do {
            try FileManager.default.moveItem(at: incoming, to: destination)
        } catch {
            if FileManager.default.fileExists(atPath: retired.path), !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.moveItem(at: retired, to: destination)
            }
            throw error
        }
    }

    private func discardRetired(_ destination: URL) throws {
        let retired = destination.appendingPathExtension("retired")
        guard FileManager.default.fileExists(atPath: retired.path) else { return }
        try FileManager.default.removeItem(at: retired)
    }

    private func restoreRetired(_ destination: URL) throws {
        let retired = destination.appendingPathExtension("retired")
        guard FileManager.default.fileExists(atPath: retired.path) else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: retired, to: destination)
    }

    private static func articleDirectory(root: URL, materialID: String) -> URL {
        let name = Data(materialID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return root.appending(path: "articles").appending(path: name)
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

    public static func acceptsService(_ url: URL, insecureLAN: Bool) -> Bool {
        if url.scheme == "https" { return true }
        guard url.scheme == "http", let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }
        guard insecureLAN else { return false }
        if host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 169 && parts[1] == 254 { return true }
        return false
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
