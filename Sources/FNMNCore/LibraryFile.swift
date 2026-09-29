import Foundation

private struct Note: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let materialID: String
    let blockID: String?
    var text: String
}

public actor LibraryFile {
    /// `state.json` holds the reader's albums, marks and books; prepared articles live in `packages.json`
    /// and are written only when an import or a delete changes them; reading progress lives in `progress.json`.
    private struct UserState: Codable {
        var legacyProgress: ReadingProgress?
        var books: [BookRecord] = []
        var albums: [String] = []
        var placements: [String: [String]] = [:]
        var annotations: [Annotation] = []
        var archived: [String] = []
        var addedAt: [String: Date] = [:]
        var articleRevisions: [String: String] = [:]
        var videoFiles: [String: String] = [:]
        var browserCatalog: BrowserCatalog?
        var legacyNotes: [Note] = []
        var legacyPackages: [ImportPackage]?

        /// Older files called albums `folders` and annotations `highlights`, and kept packages, block notes
        /// and reading progress inline.
        enum CodingKeys: String, CodingKey {
            case books, albums, placements, annotations, archived, addedAt, articleRevisions, videoFiles, browserCatalog
            case folders, highlights, notes, packages, positions, readThrough, readings
        }

        init(_ snapshot: LibrarySnapshot) {
            books = snapshot.books
            albums = snapshot.albums
            placements = snapshot.placements
            annotations = snapshot.annotations
            archived = snapshot.archived
            addedAt = snapshot.addedAt
            articleRevisions = snapshot.articleRevisions
            videoFiles = snapshot.videoFiles
            browserCatalog = snapshot.browserCatalog
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.positions) || container.contains(.readThrough) || container.contains(.readings) {
                var progress = ReadingProgress()
                progress.positions = try container.decodeIfPresent([String: ReadingPosition].self, forKey: .positions) ?? [:]
                progress.readThrough = try container.decodeIfPresent([String: Int].self, forKey: .readThrough) ?? [:]
                progress.readings = try container.decodeIfPresent([String: MaterialReading].self, forKey: .readings) ?? [:]
                legacyProgress = progress
            }
            books = try container.decodeIfPresent([BookRecord].self, forKey: .books) ?? []
            albums = try container.decodeIfPresent([String].self, forKey: .albums)
                ?? container.decodeIfPresent([String].self, forKey: .folders) ?? []
            placements = try container.decodeIfPresent([String: [String]].self, forKey: .placements) ?? [:]
            annotations = try container.decodeIfPresent([Annotation].self, forKey: .annotations)
                ?? container.decodeIfPresent([Annotation].self, forKey: .highlights) ?? []
            archived = try container.decodeIfPresent([String].self, forKey: .archived) ?? []
            addedAt = try container.decodeIfPresent([String: Date].self, forKey: .addedAt) ?? [:]
            articleRevisions = try container.decodeIfPresent([String: String].self, forKey: .articleRevisions) ?? [:]
            videoFiles = try container.decodeIfPresent([String: String].self, forKey: .videoFiles) ?? [:]
            browserCatalog = try container.decodeIfPresent(BrowserCatalog.self, forKey: .browserCatalog)
            legacyNotes = try container.decodeIfPresent([Note].self, forKey: .notes) ?? []
            legacyPackages = try container.decodeIfPresent([ImportPackage].self, forKey: .packages)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(books, forKey: .books)
            try container.encode(albums, forKey: .albums)
            try container.encode(placements, forKey: .placements)
            try container.encode(annotations, forKey: .annotations)
            try container.encode(archived, forKey: .archived)
            try container.encode(addedAt, forKey: .addedAt)
            try container.encode(articleRevisions, forKey: .articleRevisions)
            try container.encode(videoFiles, forKey: .videoFiles)
            try container.encodeIfPresent(browserCatalog, forKey: .browserCatalog)
        }

        func apply(to snapshot: inout LibrarySnapshot) {
            snapshot.books = books
            snapshot.albums = albums
            snapshot.placements = placements
            snapshot.annotations = annotations
            snapshot.archived = archived
            snapshot.addedAt = addedAt
            snapshot.articleRevisions = articleRevisions
            snapshot.videoFiles = videoFiles
            snapshot.browserCatalog = browserCatalog
        }
    }

    public nonisolated let root: URL
    public private(set) var corruptPackageNames: [String] = []
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) {
        root = url
    }

    private var stateURL: URL { root.appending(path: "state.json") }
    private var packagesURL: URL { root.appending(path: "packages.json") }
    private var progressURL: URL { root.appending(path: "progress.json") }

    public func load() throws -> (catalog: LibrarySnapshot, progress: ReadingProgress) {
        try recoverReplacedDirectories(in: root.appending(path: "books"))
        var snapshot = LibrarySnapshot()
        var legacyNotes: [Note] = []
        var legacyPackages: [ImportPackage]?
        var legacyProgress: ReadingProgress?
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let state = try decoder.decode(UserState.self, from: Data(contentsOf: stateURL))
            state.apply(to: &snapshot)
            legacyNotes = state.legacyNotes
            legacyPackages = state.legacyPackages
            legacyProgress = state.legacyProgress
        }
        var migrated = false
        if FileManager.default.fileExists(atPath: packagesURL.path) {
            snapshot.packages = try decoder.decode([ImportPackage].self, from: Data(contentsOf: packagesURL))
            corruptPackageNames = []
        } else if let legacyPackages {
            snapshot.packages = legacyPackages
            corruptPackageNames = []
            migrated = true
        } else {
            snapshot.packages = readLegacyPackages()
            migrated = !snapshot.packages.isEmpty
        }
        try sweepUnreferencedBooks(snapshot)
        try sweepArticleRevisions(snapshot)
        let foldedNotes = absorbLegacyNotes(legacyNotes, into: &snapshot)
        // Progress moves out of `state.json` first, so a crash in between never loses it.
        let storedProgress = FileManager.default.fileExists(atPath: progressURL.path)
        var progress = storedProgress
            ? try decoder.decode(ReadingProgress.self, from: Data(contentsOf: progressURL))
            : legacyProgress ?? ReadingProgress()
        let foldedPlaces = absorbLegacyArticlePositions(into: &progress, packages: snapshot.packages)
        if foldedPlaces || (!storedProgress && legacyProgress != nil) {
            try saveProgress(progress)
        }
        if migrated || foldedNotes || legacyProgress != nil {
            try save(snapshot)
        }
        return (snapshot, progress)
    }

    public func saveProgress(_ progress: ReadingProgress) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(progress).write(to: progressURL, options: .atomic)
    }

    /// Writes the reader's state, and the packages only when they differ from `previous`;
    /// then removes files of books and articles the snapshot no longer holds.
    public func save(_ snapshot: LibrarySnapshot, previous: LibrarySnapshot? = nil) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if previous?.packages != snapshot.packages {
            try encoder.encode(snapshot.packages).write(to: packagesURL, options: .atomic)
        }
        try encoder.encode(UserState(snapshot)).write(to: stateURL, options: .atomic)
        guard let previous else { return }
        if previous.books != snapshot.books { try sweepUnreferencedBooks(snapshot) }
        if previous.articleRevisions != snapshot.articleRevisions { try sweepArticleRevisions(snapshot) }
        if previous.videoFiles != snapshot.videoFiles { try sweepVideoFiles(snapshot) }
    }

    /// Moves a downloaded video into the library and records it for the item.
    public func storeVideoFile(_ itemID: String, from download: URL, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        let folder = root.appending(path: "videos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".mp4"
        try FileManager.default.moveItem(at: download, to: folder.appending(path: name))
        var next = snapshot
        next.videoFiles[itemID] = name
        try save(next, previous: snapshot)
        return next
    }

    public static func videoFile(root: URL, name: String) -> URL {
        root.appending(path: "videos").appending(path: name)
    }

    private func sweepVideoFiles(_ snapshot: LibrarySnapshot) throws {
        let folder = root.appending(path: "videos")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        let kept = Set(snapshot.videoFiles.values)
        for file in files where !kept.contains(file.lastPathComponent) {
            try FileManager.default.removeItem(at: file)
        }
    }

    public func storeArticle(_ package: ImportPackage, files: [String: Data], into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        var next = snapshot
        try next.importPackage(package, at: .now)
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

    public func storeBrowserLibrary(from source: URL, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        let catalog = try decoder.decode(BrowserCatalog.self, from: Data(contentsOf: source.appending(path: "catalog.json")))
        let deliveries = try FileManager.default.contentsOfDirectory(
            at: source.appending(path: "deliveries"), includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var next = snapshot
        next.retireAlbums(catalog.collections.map(\.name))
        next.browserCatalog = catalog
        for url in deliveries {
            let delivery = try decoder.decode(BrowserDelivery.self, from: Data(contentsOf: url))
            try next.importPackage(delivery.package, at: .now)
            if !delivery.files.isEmpty {
                let revision = UUID().uuidString
                try writeArticleRevision(delivery.files, materialID: delivery.package.material.id, revision: revision)
                next.articleRevisions[delivery.package.material.id] = revision
            }
        }
        try save(next)
        try sweepArticleRevisions(next)
        return next
    }

    private struct BrowserDelivery: Decodable {
        let package: ImportPackage
        let files: [String: Data]

        init(from decoder: Decoder) throws {
            package = try ImportPackage(from: decoder)
            files = try decoder.container(keyedBy: CodingKeys.self).decode([String: Data].self, forKey: .files)
        }

        private enum CodingKeys: String, CodingKey { case files }
    }

    public func storeBook(_ record: BookRecord, from source: URL, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        let previousName = snapshot.books.first { $0.id == record.id }?.directoryName
        var next = snapshot
        next.importBook(record, at: .now)
        let books = root.appending(path: "books")
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
            try save(next, previous: snapshot)
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

    public func removeBook(named directoryName: String) throws {
        let destination = root.appending(path: "books").appending(path: directoryName)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    public func bookText(directoryName: String, contentFile: String) throws -> String {
        guard let url = Self.bookFile(root: root, directoryName: directoryName, path: contentFile) else {
            throw LibraryError.escapedPath
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The folder a material's relative picture and video paths resolve against.
    public static func articleFolder(root: URL, materialID: String, revision: String?) -> URL {
        let folder = articleDirectory(root: root, materialID: materialID)
        guard let revision, !revision.isEmpty else { return folder }
        return folder.appending(path: revision, directoryHint: .isDirectory)
    }

    public static func bookFolder(root: URL, directoryName: String) -> URL {
        root.appending(path: "books").appending(path: directoryName, directoryHint: .isDirectory)
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
            guard let destination = Self.articleFile(root: root, materialID: materialID, path: path, revision: revision) else {
                throw LibraryError.escapedPath
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
    }

    private func removeArticleRevision(materialID: String, revision: String) throws {
        let folder = Self.articleDirectory(root: root, materialID: materialID).appending(path: revision)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    private func absorbLegacyNotes(_ notes: [Note], into snapshot: inout LibrarySnapshot) -> Bool {
        guard !notes.isEmpty else { return false }
        for note in notes where !snapshot.annotations.contains(where: { $0.id == note.id }) {
            let piece: Int
            if let blockID = note.blockID, let index = ReadingPosition(blockID: blockID).pieceIndex {
                piece = index
            } else {
                piece = 0
            }
            snapshot.annotations.append(
                Annotation(id: note.id, materialID: note.materialID, piece: piece, quote: "", note: note.text)
            )
        }
        return true
    }

    private func absorbLegacyArticlePositions(into progress: inout ReadingProgress, packages: [ImportPackage]) -> Bool {
        var changed = false
        for (materialID, position) in progress.positions {
            guard let package = packages.first(where: { $0.material.id == materialID }),
                  let piece = ArticleBody.legacyPiece(for: position, in: package) else { continue }
            progress.positions[materialID] = .piece(piece)
            changed = true
        }
        return changed
    }

    private func readLegacyPackages() -> [ImportPackage] {
        let packagesDirectory = root.appending(path: "packages")
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
        let books = root.appending(path: "books")
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
        let articles = root.appending(path: "articles")
        guard let keys = try? FileManager.default.contentsOfDirectory(at: articles, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let live = Dictionary(uniqueKeysWithValues: snapshot.articleRevisions.map {
            (Self.articleDirectory(root: root, materialID: $0.key).lastPathComponent, $0.value)
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
