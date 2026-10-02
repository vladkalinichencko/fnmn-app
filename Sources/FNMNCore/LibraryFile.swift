import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct Note: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let materialID: String
    let blockID: String?
    var text: String
}

/// The library's files. Materials live in the FNMN folder in iCloud Drive: `deliveries/` holds one archive
/// per article, video or book, `state/` each device's journal. The app keeps what it
/// needs to list and resume them: the catalog, small cover pictures, reading progress and its own state, and
/// in the cache the unpacked copies of materials it has opened.
public actor LibraryFile {
    /// `state.json` holds the reader's albums and marks; the catalog's article entries live in
    /// `articles.json` and are written only when an import or a delete changes them; reading progress lives in
    /// `progress.json`.
    private struct UserState: Codable {
        var legacyProgress: ReadingProgress?
        var albums: [String] = []
        var placements: [String: [String]] = [:]
        var annotations: [Annotation] = []
        var archived: [String] = []
        var addedAt: [String: Date] = [:]
        var articleRevisions: [String: String] = [:]
        /// Nil in a file written before deletions were kept.
        var deletedAt: [String: Date]?
        /// Videos an older version saved inside the app, item id → file name in `videos/`, until they move
        /// into the FNMN folder's `originals/`.
        var legacyVideoFiles: [String: String] = [:]
        var browserCatalog: BrowserCatalog?
        var legacyNotes: [Note] = []
        var legacyPackages: [ImportPackage]?

        /// Older files called albums `folders` and annotations `highlights`, and kept packages, block notes
        /// and reading progress inline.
        enum CodingKeys: String, CodingKey {
            case albums, placements, annotations, archived, addedAt, articleRevisions, deletedAt, videoFiles, browserCatalog
            case folders, highlights, notes, packages, positions, readThrough, readings
        }

        init(_ snapshot: LibrarySnapshot) {
            albums = snapshot.albums
            placements = snapshot.placements
            annotations = snapshot.annotations
            archived = snapshot.archived
            addedAt = snapshot.addedAt
            articleRevisions = snapshot.articleRevisions
            deletedAt = snapshot.deletedAt
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
            albums = try container.decodeIfPresent([String].self, forKey: .albums)
                ?? container.decodeIfPresent([String].self, forKey: .folders) ?? []
            placements = try container.decodeIfPresent([String: [String]].self, forKey: .placements) ?? [:]
            annotations = try container.decodeIfPresent(StoredAnnotations.self, forKey: .annotations)?.records
                ?? container.decodeIfPresent(StoredAnnotations.self, forKey: .highlights)?.records ?? []
            archived = try container.decodeIfPresent([String].self, forKey: .archived) ?? []
            addedAt = try container.decodeIfPresent([String: Date].self, forKey: .addedAt) ?? [:]
            articleRevisions = try container.decodeIfPresent([String: String].self, forKey: .articleRevisions) ?? [:]
            deletedAt = try container.decodeIfPresent([String: Date].self, forKey: .deletedAt)
            legacyVideoFiles = try container.decodeIfPresent([String: String].self, forKey: .videoFiles) ?? [:]
            browserCatalog = try container.decodeIfPresent(BrowserCatalog.self, forKey: .browserCatalog)
            legacyNotes = try container.decodeIfPresent([Note].self, forKey: .notes) ?? []
            legacyPackages = try container.decodeIfPresent([ImportPackage].self, forKey: .packages)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(albums, forKey: .albums)
            try container.encode(placements, forKey: .placements)
            try container.encode(annotations, forKey: .annotations)
            try container.encode(archived, forKey: .archived)
            try container.encode(addedAt, forKey: .addedAt)
            try container.encode(articleRevisions, forKey: .articleRevisions)
            try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
            if !legacyVideoFiles.isEmpty { try container.encode(legacyVideoFiles, forKey: .videoFiles) }
            try container.encodeIfPresent(browserCatalog, forKey: .browserCatalog)
        }

        func apply(to snapshot: inout LibrarySnapshot) {
            snapshot.albums = albums
            snapshot.placements = placements
            snapshot.annotations = annotations
            snapshot.archived = archived
            snapshot.addedAt = addedAt
            snapshot.articleRevisions = articleRevisions
            snapshot.deletedAt = deletedAt ?? [:]
            snapshot.browserCatalog = browserCatalog
        }
    }

    public nonisolated let root: URL
    /// Unpacked copies of materials, in a folder the system may empty when space runs low.
    public nonisolated let cache: URL
    /// The FNMN folder in iCloud Drive, once the app has access to it.
    public private(set) var cloudFolder: URL?
    public private(set) var corruptPackageNames: [String] = []
    private var legacyVideoFiles: [String: String] = [:]
    /// False for state written before deletions were kept: the deliveries of materials deleted then are still in
    /// the FNMN folder, and the journals, which hold those deletions, are read once to fill them in.
    private var deletionsKnown = true
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL, cache: URL? = nil) {
        root = url
        self.cache = cache ?? url.appending(path: "cache")
    }

    public func useCloudFolder(_ folder: URL?) {
        cloudFolder = folder
    }

    private func requireCloudFolder() throws -> URL {
        guard let cloudFolder else { throw LibraryError.cloudFolderMissing }
        return cloudFolder
    }

    private var stateURL: URL { root.appending(path: "state.json") }
    private var articlesURL: URL { root.appending(path: "articles.json") }
    /// Older libraries kept every article with its text in one file.
    private var packagesURL: URL { root.appending(path: "packages.json") }
    private var progressURL: URL { root.appending(path: "progress.json") }
    private static let textName = "text.json"

    public func load() throws -> (catalog: LibrarySnapshot, progress: ReadingProgress) {
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
            legacyVideoFiles = state.legacyVideoFiles
            deletionsKnown = state.deletedAt != nil
        }
        corruptPackageNames = []
        var packages: [ImportPackage] = []
        if FileManager.default.fileExists(atPath: articlesURL.path) {
            snapshot.articles = try decoder.decode([ArticleEntry].self, from: Data(contentsOf: articlesURL))
        } else if FileManager.default.fileExists(atPath: packagesURL.path) {
            packages = try decoder.decode([ImportPackage].self, from: Data(contentsOf: packagesURL))
        } else if let legacyPackages {
            packages = legacyPackages
        } else {
            packages = readLegacyPackages()
        }
        // Texts from the older layouts go to their article folders in the app, until `moveIntoCloud` takes them.
        for package in packages {
            try writeText(package, revision: snapshot.articleRevisions[package.material.id])
        }
        snapshot.articles.append(contentsOf: packages.map { ArticleEntry($0) })
        try sweepArticleRevisions(snapshot)
        let foldedNotes = absorbLegacyNotes(legacyNotes, into: &snapshot)
        // Progress moves out of `state.json` first, so a crash in between never loses it.
        let storedProgress = FileManager.default.fileExists(atPath: progressURL.path)
        var progress = storedProgress
            ? try decoder.decode(ReadingProgress.self, from: Data(contentsOf: progressURL))
            : legacyProgress ?? ReadingProgress()
        let foldedPlaces = absorbLegacyArticlePositions(into: &progress, packages: packages)
        if foldedPlaces || (!storedProgress && legacyProgress != nil) {
            try saveProgress(progress)
        }
        if !packages.isEmpty || foldedNotes || legacyProgress != nil {
            try save(snapshot)
        }
        if FileManager.default.fileExists(atPath: packagesURL.path) {
            try FileManager.default.removeItem(at: packagesURL)
        }
        // The oldest layout kept one file per package; once every one of them is in, the folder goes.
        // A file that could not be read keeps the folder, so it is not lost.
        let legacyFolder = root.appending(path: "packages")
        if corruptPackageNames.isEmpty, FileManager.default.fileExists(atPath: legacyFolder.path) {
            try FileManager.default.removeItem(at: legacyFolder)
        }
        return (snapshot, progress)
    }

    public func saveProgress(_ progress: ReadingProgress) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(progress).write(to: progressURL, options: .atomic)
    }

    /// Writes the reader's state, and the article entries only when they differ from `previous`;
    /// then removes the app's copies of materials the catalog no longer holds.
    public func save(_ snapshot: LibrarySnapshot, previous: LibrarySnapshot? = nil) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if previous?.articles != snapshot.articles {
            try encoder.encode(snapshot.articles).write(to: articlesURL, options: .atomic)
        }
        var state = UserState(snapshot)
        state.legacyVideoFiles = legacyVideoFiles
        try encoder.encode(state).write(to: stateURL, options: .atomic)
        guard let previous else { return }
        if previous.articles != snapshot.articles || previous.articleRevisions != snapshot.articleRevisions {
            try sweepArticleRevisions(snapshot)
        }
    }

    // MARK: Originals

    /// Keeps a copy of the file a material was made from, or of a video saved for the system player, in the
    /// FNMN folder's `originals/`, named like the material's delivery with the file's own extension.
    public func storeOriginal(_ file: URL, of entry: ArticleEntry) throws {
        guard let name = entry.originalName(pathExtension: file.pathExtension) else { throw LibraryError.cloudFolderMissing }
        try placeInCloud(file, at: try requireCloudFolder().appending(path: "originals").appending(path: name))
    }

    public func removeOriginal(_ file: URL) throws {
        var coordination: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forDeleting, error: &coordination) { url in
            do { try FileManager.default.removeItem(at: url) } catch { failure = error }
        }
        if let error = coordination ?? failure { throw error }
    }

    /// The archive of a deleted material leaves the FNMN folder, so no device is left a file to read it in again.
    public func removeDelivery(of entry: ArticleEntry) throws {
        guard let archive = deliveryURL(of: entry) else { return }
        do {
            try removeOriginal(archive)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {}
    }

    // MARK: Adding materials

    /// A link or file kept as it is, made on this phone, becomes a delivery like any other.
    public func storeMade(_ package: ImportPackage, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        let archive = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".tar")
        defer { try? FileManager.default.removeItem(at: archive) }
        try DeliveryArchive.write(package, files: [], to: archive)
        return try storeArticle(archive: archive, into: snapshot)
    }

    /// A delivery archive the server prepared for this phone joins the others in the FNMN folder.
    public func storeArticle(archive: URL, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        let package = try DeliveryArchive(url: archive).unpack { _, _ in nil }
        let destination = try requireCloudFolder().appending(path: "deliveries").appending(path: Self.deliveryName(package.material.id))
        try placeInCloud(archive, at: destination)
        let next = try addCloudDelivery(destination, into: snapshot)
        try save(next, previous: snapshot)
        return next
    }

    /// A picked file kept as it is, known by its bytes, which are hashed here so the main thread never reads the file.
    public func package(ofFile file: URL) throws -> ImportPackage {
        try .file(file)
    }

    /// The first step of a browser library import: its catalog of sources, whose reviewed albums replace
    /// the browser's collections.
    public func applyBrowserCatalog(from source: URL, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        let catalog = try decoder.decode(BrowserCatalog.self, from: Data(contentsOf: source.appending(path: "catalog.json")))
        var next = snapshot
        next.retireAlbums(catalog.collections.map(\.name))
        next.browserCatalog = catalog
        return next
    }

    /// One delivery in the FNMN folder: the package enters the catalog, and of its files only the cover is
    /// kept, as a small picture; the archive stays in iCloud and is unpacked when the reader opens it.
    public func addCloudDelivery(_ archive: URL, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        let cover = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cover) }
        var hasCover = false
        let package = try DeliveryArchive(url: archive).unpack { package, path in
            guard case let .articleFile(_, coverPath)? = package.cover, coverPath == path else { return nil }
            hasCover = true
            return cover
        }
        if hasCover {
            try writeThumbnail(of: cover, to: Self.coverFile(root: root, materialID: package.material.id))
        }
        var next = snapshot
        try next.importPackage(package, at: .now, delivery: archive.lastPathComponent, deliveredAt: Self.changeDate(of: archive))
        next.articleRevisions[package.material.id] = nil
        return next
    }

    /// Deliveries in the FNMN folder this device has not read as they are now: ones another device added, and
    /// ones it rewrote with a prepared material. A delivery whose material was deleted after the file last changed
    /// stays out. A file still only in iCloud has no date here yet, so a rewrite of it waits until it is on the device.
    /// Returns the catalog too, with the deletions it learned from the journals.
    public func changedDeliveries(_ files: [URL], in snapshot: LibrarySnapshot) throws -> (deliveries: [URL], snapshot: LibrarySnapshot) {
        var snapshot = snapshot
        if !deletionsKnown {
            // An empty device name reads every device's journal, this one's too.
            for event in try unreadJournalEvents(except: "", sync: JournalSync()).events {
                guard case let .library(.delete(itemID)) = event.change else { continue }
                snapshot.deletedAt[itemID] = max(snapshot.deletedAt[itemID] ?? .distantPast, event.time)
            }
            deletionsKnown = true
        }
        let read = Dictionary(snapshot.articles.compactMap { entry in entry.delivery.map { ($0, entry.deliveredAt) } }, uniquingKeysWith: { first, _ in first })
        let deleted = Dictionary(snapshot.deletedAt.map { (Self.deliveryName($0.key), $0.value) }, uniquingKeysWith: max)
        let changed = files.filter { file in
            let changedAt = Self.changeDate(of: file)
            switch read[file.lastPathComponent] {
            case let readAt??: return changedAt.map { $0 != readAt } ?? false
            case .some(nil): return false // read before this device kept the dates
            case nil:
                guard let deletedAt = deleted[file.lastPathComponent] else { return true }
                return changedAt.map { $0 > deletedAt } ?? false
            }
        }
        return (changed, snapshot)
    }

    /// Read fresh: a URL keeps the values it read before, which would hide a rewrite.
    private static func changeDate(of file: URL) -> Date? {
        var file = file
        file.removeAllCachedResourceValues()
        return try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// The first time the FNMN folder is linked, what an older version kept inside the app moves there: each
    /// article becomes an archive in `deliveries/`, each saved video an original in `originals/`. The app's
    /// copies then go; books come from the server as deliveries of their own.
    public func moveIntoCloud(_ snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        let cloud = try requireCloudFolder()
        var next = snapshot
        for entry in snapshot.articles where entry.delivery == nil {
            let id = entry.material.id
            let folder = Self.articleFolder(root: root, materialID: id, revision: snapshot.articleRevisions[id])
            let package = try decoder.decode(ImportPackage.self, from: Data(contentsOf: folder.appending(path: Self.textName)))
            let files = try (FileManager.default.subpathsOfDirectory(atPath: folder.path))
                .filter { $0 != Self.textName && !$0.hasPrefix(".") }
                .map { (path: $0, source: folder.appending(path: $0)) }
                .filter { (try? $0.source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            let archive = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".tar")
            defer { try? FileManager.default.removeItem(at: archive) }
            try DeliveryArchive.write(package, files: files, to: archive)
            let destination = cloud.appending(path: "deliveries").appending(path: Self.deliveryName(id))
            try placeInCloud(archive, at: destination)
            next = try addCloudDelivery(destination, into: next)
        }
        let appBooks = root.appending(path: "books")
        if FileManager.default.fileExists(atPath: appBooks.path) {
            try FileManager.default.removeItem(at: appBooks)
        }
        let appVideos = root.appending(path: "videos")
        for (itemID, name) in legacyVideoFiles {
            let video = appVideos.appending(path: name)
            guard let entry = next.articles.first(where: { $0.material.id == itemID }),
                  FileManager.default.fileExists(atPath: video.path) else { continue }
            try storeOriginal(video, of: entry)
        }
        legacyVideoFiles = [:]
        if FileManager.default.fileExists(atPath: appVideos.path) {
            try FileManager.default.removeItem(at: appVideos)
        }
        try save(next, previous: snapshot)
        let appArticles = root.appending(path: "articles")
        if FileManager.default.fileExists(atPath: appArticles.path) {
            try FileManager.default.removeItem(at: appArticles)
        }
        return next
    }

    /// Whether anything still waits inside the app for `moveIntoCloud`.
    public func holdsMaterialsInApp(_ snapshot: LibrarySnapshot) -> Bool {
        snapshot.articles.contains { $0.delivery == nil }
            || FileManager.default.fileExists(atPath: root.appending(path: "books").path)
            || FileManager.default.fileExists(atPath: root.appending(path: "videos").path)
    }

    private static func deliveryName(_ materialID: String) -> String {
        SHA256.hash(data: Data(materialID.utf8)).map { String(format: "%02x", $0) }.joined() + ".tar"
    }

    // MARK: Opening materials

    /// Where a material is unpacked; a new text gets a new folder.
    public nonisolated func cachedFolder(of entry: ArticleEntry) -> URL {
        cache.appending(path: "articles")
            .appending(path: Self.articleDirectory(root: root, materialID: entry.material.id).lastPathComponent)
            .appending(path: entry.textDigest, directoryHint: .isDirectory)
    }

    public func isUnpacked(_ entry: ArticleEntry) -> Bool {
        FileManager.default.fileExists(atPath: cachedFolder(of: entry).appending(path: Self.textName).path)
    }

    /// The material's archive in the FNMN folder, once the folder is linked.
    public func deliveryURL(of entry: ArticleEntry) -> URL? {
        guard let cloudFolder, let name = entry.delivery else { return nil }
        return cloudFolder.appending(path: "deliveries").appending(path: name)
    }

    /// Opens a material from its unpacked copy, unpacking the archive first when the system has emptied the
    /// cache; the caller brings the archive down from iCloud before that.
    public func openCloudArticle(_ entry: ArticleEntry) throws -> ImportPackage {
        let folder = cachedFolder(of: entry)
        let text = folder.appending(path: Self.textName)
        if !FileManager.default.fileExists(atPath: text.path) {
            guard let archive = deliveryURL(of: entry) else { throw LibraryError.cloudFolderMissing }
            let incoming = folder.appendingPathExtension("incoming")
            try? FileManager.default.removeItem(at: incoming)
            let package = try DeliveryArchive(url: archive).unpack { _, path in
                guard let file = Self.contained(path, in: incoming) else { throw LibraryError.escapedPath }
                return file
            }
            try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
            try encoder.encode(package).write(to: incoming.appending(path: Self.textName))
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.moveItem(at: incoming, to: folder)
        }
        return try decoder.decode(ImportPackage.self, from: Data(contentsOf: text))
    }

    // MARK: Journals

    /// Where each device's journal lives, once the FNMN folder is linked.
    public func journalFolder() -> URL? {
        cloudFolder?.appending(path: "state", directoryHint: .isDirectory)
    }

    public func loadSync() throws -> JournalSync {
        let url = root.appending(path: "sync.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return JournalSync() }
        return try decoder.decode(JournalSync.self, from: Data(contentsOf: url))
    }

    public func saveSync(_ sync: JournalSync) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(sync).write(to: root.appending(path: "sync.json"), options: .atomic)
    }

    /// Appends this device's changes to its own journal, one JSON line each, under file coordination. A journal
    /// grown past `compactingAfter` lines is folded down into a file of the next generation, which the other
    /// devices read from its start, and the old file goes.
    public func appendJournal(_ events: [JournalEvent], device: String, compactingAfter limit: Int = 2000) throws {
        guard let folder = journalFolder(), !events.isEmpty else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let journal = ownJournal(of: device, in: folder)
        try coordinatedWrite(at: journal, options: .forMerging) { url in
            let lines = Data(try self.lines(of: events).utf8)
            guard FileManager.default.fileExists(atPath: url.path) else {
                try lines.write(to: url)
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: lines)
        }
        let written = try readJournal(journal)
        guard written.count > limit else { return }
        let generation = folder.appending(path: "\(device).\(Int(Date().timeIntervalSince1970 * 1000)).jsonl")
        let folded = try lines(of: compacted(written))
        try coordinatedWrite(at: generation, options: .forReplacing) { url in try Data(folded.utf8).write(to: url) }
        try coordinatedWrite(at: journal, options: .forDeleting) { url in try FileManager.default.removeItem(at: url) }
    }

    /// This device's journal: `<device>.jsonl`, or `<device>.<generation>.jsonl` once it has been folded down.
    private func ownJournal(of device: String, in folder: URL) -> URL {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { Self.isJournal($0, of: device) }.max { $0.lastPathComponent < $1.lastPathComponent }
            ?? folder.appending(path: "\(device).jsonl")
    }

    private static func isJournal(_ file: URL, of device: String) -> Bool {
        file.pathExtension == "jsonl"
            && (file.lastPathComponent == "\(device).jsonl" || file.lastPathComponent.hasPrefix("\(device)."))
    }

    private func lines(of events: [JournalEvent]) throws -> String {
        try events.map { String(decoding: try encoder.encode($0), as: UTF8.self) + "\n" }.joined()
    }

    private func readJournal(_ file: URL) throws -> [JournalEvent] {
        var text = ""
        try coordinatedRead(at: file) { url in text = (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
        return text.split(separator: "\n").compactMap { try? decoder.decode(JournalEvent.self, from: Data($0.utf8)) }
    }

    private func coordinatedWrite(at file: URL, options: NSFileCoordinator.WritingOptions, _ write: (URL) throws -> Void) throws {
        var coordination: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: options, error: &coordination) { url in
            do { try write(url) } catch { failure = error }
        }
        if let error = coordination ?? failure { throw error }
    }

    private func coordinatedRead(at file: URL, _ read: (URL) -> Void) throws {
        var coordination: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordination, byAccessor: read)
        if let coordination { throw coordination }
    }

    /// The other devices' changes this device has not applied yet, and how many lines of each journal are
    /// read after them. A line that does not decode stops that journal there, to be read again next time.
    /// A journal another device has folded into a new generation is gone, and so is what was known of it.
    public func unreadJournalEvents(except device: String, sync: JournalSync) throws -> (events: [JournalEvent], applied: [String: Int]) {
        guard let folder = journalFolder(),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return ([], sync.applied)
        }
        let others = files.filter { $0.pathExtension == "jsonl" && !Self.isJournal($0, of: device) }
        var applied = sync.applied.filter { name, _ in others.contains { $0.lastPathComponent == name } }
        var events: [JournalEvent] = []
        for file in others {
            let name = file.lastPathComponent
            var text = ""
            try coordinatedRead(at: file) { url in text = (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            var read = applied[name] ?? 0
            for line in lines.dropFirst(read) {
                guard let event = try? decoder.decode(JournalEvent.self, from: Data(line.utf8)) else { break }
                events.append(event)
                read += 1
            }
            applied[name] = read
        }
        return (events, applied)
    }

    // MARK: Files in iCloud and in the app

    /// The small cover picture kept in the app for a material.
    public static func coverFile(root: URL, materialID: String) -> URL {
        root.appending(path: "covers").appending(path: articleDirectory(root: root, materialID: materialID).lastPathComponent)
    }

    /// A copy placed beside and renamed over, under file coordination, is a new version to iCloud, not a conflict.
    private func placeInCloud(_ item: URL, at destination: URL) throws {
        let incoming = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.copyItem(at: item, to: incoming)
        defer { try? FileManager.default.removeItem(at: incoming) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordination: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordination) { url in
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: incoming)
                } else {
                    try FileManager.default.moveItem(at: incoming, to: url)
                }
            } catch {
                failure = error
            }
        }
        if let error = coordination ?? failure { throw error }
    }

    /// Covers are shown on tiles a few hundred points wide, so 800 pixels is enough; a picture with
    /// transparency stays a PNG, so it does not turn black behind. A cover only decorates its tile, so a picture
    /// ImageIO cannot read leaves the tile without one instead of stopping the import.
    private func writeThumbnail(of picture: URL, to destination: URL) throws {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 800,
        ]
        guard let source = CGImageSourceCreateWithURL(picture as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return
        }
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type = (opaque ? UTType.jpeg : UTType.png).identifier as CFString
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let file = CGImageDestinationCreateWithURL(destination as CFURL, type, 1, nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
        }
        CGImageDestinationAddImage(file, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(file) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
        }
    }

    // MARK: Older layouts

    /// The whole package of an article an older version kept inside the app.
    public func article(_ materialID: String, revision: String?) throws -> ImportPackage {
        guard let url = Self.articleFile(root: root, materialID: materialID, path: Self.textName, revision: revision) else {
            throw LibraryError.escapedPath
        }
        return try decoder.decode(ImportPackage.self, from: Data(contentsOf: url))
    }

    private func writeText(_ package: ImportPackage, revision: String?) throws {
        guard let url = Self.articleFile(root: root, materialID: package.material.id, path: Self.textName, revision: revision) else {
            throw LibraryError.escapedPath
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(package).write(to: url, options: .atomic)
    }

    /// The folder in the app where an older version kept an article's text and pictures.
    public static func articleFolder(root: URL, materialID: String, revision: String?) -> URL {
        let folder = articleDirectory(root: root, materialID: materialID)
        guard let revision, !revision.isEmpty else { return folder }
        return folder.appending(path: revision, directoryHint: .isDirectory)
    }

    public static func articleFile(root: URL, materialID: String, path: String, revision: String? = nil) -> URL? {
        guard revision?.contains("/") != true, revision?.contains("..") != true else { return nil }
        var folder = articleDirectory(root: root, materialID: materialID)
        if let revision, !revision.isEmpty {
            folder = folder.appending(path: revision)
        }
        return contained(path, in: folder)
    }

    /// A relative path from a package, only when it stays inside the folder.
    static func contained(_ path: String, in folder: URL) -> URL? {
        let folder = folder.standardizedFileURL
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("..") else { return nil }
        let destination = folder.appending(path: path).standardizedFileURL
        guard destination.path == folder.path || destination.path.hasPrefix(folder.path + "/") else { return nil }
        return destination
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
                Annotation(id: note.id, materialID: note.materialID, piece: piece, text: "", note: note.text)
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

    // MARK: Sweeping

    /// An article an older version kept in the app keeps only its current revision until it moves into the
    /// FNMN folder; for a material there, its cover picture and unpacked copy go with it, and so does a copy of
    /// an older text.
    private func sweepArticleRevisions(_ snapshot: LibrarySnapshot) throws {
        try sweepCloudCopies(snapshot)
        let articles = root.appending(path: "articles")
        guard let keys = try? FileManager.default.contentsOfDirectory(at: articles, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let live = Dictionary(uniqueKeysWithValues: snapshot.articleRevisions.map {
            (Self.articleDirectory(root: root, materialID: $0.key).lastPathComponent, $0.value)
        })
        let known = Set(snapshot.articles.filter { $0.delivery == nil }.map {
            Self.articleDirectory(root: root, materialID: $0.material.id).lastPathComponent
        })
        for keyURL in keys {
            guard known.contains(keyURL.lastPathComponent) else {
                try FileManager.default.removeItem(at: keyURL)
                continue
            }
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

    private func sweepCloudCopies(_ snapshot: LibrarySnapshot) throws {
        let cloud = snapshot.articles.filter { $0.delivery != nil }
        let digests = Dictionary(cloud.map { (Self.articleDirectory(root: root, materialID: $0.material.id).lastPathComponent, $0.textDigest) },
                                 uniquingKeysWith: { first, _ in first })
        let unpacked = cache.appending(path: "articles")
        for keyURL in (try? FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)) ?? [] {
            guard let digest = digests[keyURL.lastPathComponent] else {
                try FileManager.default.removeItem(at: keyURL)
                continue
            }
            for copy in (try? FileManager.default.contentsOfDirectory(at: keyURL, includingPropertiesForKeys: nil)) ?? [] where copy.lastPathComponent != digest {
                try FileManager.default.removeItem(at: copy)
            }
        }
        let covered = Set(cloud.filter { if case .stored = $0.cover { true } else { false } }.map {
            Self.coverFile(root: root, materialID: $0.material.id).lastPathComponent
        })
        for cover in (try? FileManager.default.contentsOfDirectory(at: root.appending(path: "covers"), includingPropertiesForKeys: nil)) ?? []
        where !covered.contains(cover.lastPathComponent) {
            try FileManager.default.removeItem(at: cover)
        }
    }

    private static func articleDirectory(root: URL, materialID: String) -> URL {
        let name = Data(materialID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return root.appending(path: "articles").appending(path: name)
    }
}
