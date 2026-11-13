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

public actor LibraryFile {
    private struct UserState: Codable {
        var legacyProgress: ReadingProgress?
        var albums: [String] = []
        var placements: [String: [String]] = [:]
        var annotations: [Annotation] = []
        var archived: [String] = []
        var addedAt: [String: Date] = [:]
        var articleRevisions: [String: String] = [:]
        var deletedAt: [String: Date]?
        var legacyVideoFiles: [String: String] = [:]
        var browserCatalog: BrowserCatalog?
        var legacyNotes: [Note] = []
        var legacyPackages: [ImportPackage]?

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
    public nonisolated let cache: URL
    public private(set) var cloudFolder: URL?
    public private(set) var corruptPackageNames: [String] = []
    private var legacyVideoFiles: [String: String] = [:]
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
    private var searchFolder: URL {
        root.appending(path: "search")
    }
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
        for package in packages {
            try writeText(package, revision: snapshot.articleRevisions[package.material.id])
        }
        snapshot.articles.append(contentsOf: packages.map { ArticleEntry($0) })
        try sweepArticleRevisions(snapshot)
        let foldedNotes = absorbLegacyNotes(legacyNotes, into: &snapshot)
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

    public func removeDelivery(of entry: ArticleEntry) throws {
        guard let archive = deliveryURL(of: entry) else { return }
        do {
            try removeOriginal(archive)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {}
    }


    public func storeMade(_ package: ImportPackage, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        let archive = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".tar")
        defer { try? FileManager.default.removeItem(at: archive) }
        try DeliveryArchive.write(package, files: [], to: archive)
        return try storeArticle(archive: archive, into: snapshot)
    }

    public func storeArticle(archive: URL, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {
        let package = try DeliveryArchive(url: archive).unpack { (_: ImportPackage, _) in nil }
        let destination = try requireCloudFolder().appending(path: "deliveries").appending(path: Self.deliveryName(package.material.id))
        try placeInCloud(archive, at: destination)
        let next = try addCloudDelivery(destination, into: snapshot)
        try save(next, previous: snapshot)
        return next
    }

    public func package(ofFile file: URL) throws -> ImportPackage {
        try .file(file)
    }

    public func applyBrowserCatalogIfChanged(from source: URL, into snapshot: LibrarySnapshot) async throws -> LibrarySnapshot? {
        let file = source.appending(path: "catalog.json")
        guard CloudFolder.contains(file) else {
            return nil
        }
        try await CloudFolder.download(file)
        guard let data = try? Data(contentsOf: file) else {
            throw CloudFolderError.notDownloaded(count: 1, name: file.lastPathComponent)
        }
        let catalog: BrowserCatalog
        do {
            catalog = try decoder.decode(BrowserCatalog.self, from: data)
        } catch let error as DecodingError {
            throw LibraryError.catalogMalformed("\(data.count) bytes, \(describeCatalogError(error))")
        }
        guard catalog != snapshot.browserCatalog else {
            return nil
        }
        var next = snapshot
        next.retireAlbums(catalog.collections.map(\.name))
        next.browserCatalog = catalog
        return next
    }

    private func describeCatalogError(_ error: DecodingError) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case let .keyNotFound(key, context):
            return "missing key \"\(key.stringValue)\" at \(path(context.codingPath))"
        case let .typeMismatch(_, context):
            return "wrong type at \(path(context.codingPath)): \(context.debugDescription)"
        case let .valueNotFound(_, context):
            return "missing value at \(path(context.codingPath))"
        case let .dataCorrupted(context):
            return "corrupt data at \(path(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    public func addCloudDelivery(_ archive: URL, into snapshot: LibrarySnapshot) throws -> LibrarySnapshot {        let cover = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cover) }
        var hasCover = false
        let package = try DeliveryArchive(url: archive).unpack { (package: ImportPackage, path: String) in
            guard case let .articleFile(_, coverPath)? = package.cover, coverPath == path else { return nil }
            hasCover = true
            return cover
        }
        if hasCover {
            try writeThumbnail(of: cover, to: Self.coverFile(root: root, materialID: package.material.id))
        }
        try writeSearchBody(package)
        var next = snapshot
        try next.importPackage(package, at: .now, delivery: archive.lastPathComponent, deliveredAt: Self.changeDate(of: archive))
        let remaining = Set(next.articles.map(\.material.id))
        for entry in snapshot.articles where entry.material.kind == .link && !remaining.contains(entry.material.id) {
            try? removeDelivery(of: entry)
        }
        next.articleRevisions[package.material.id] = nil
        return next
    }

    public func changedDeliveries(_ files: [URL], in snapshot: LibrarySnapshot) async throws -> (deliveries: [URL], snapshot: LibrarySnapshot) {
        var snapshot = snapshot
        if !deletionsKnown {
            for event in try await unreadJournalEvents(except: "", sync: JournalKnowledge()).events {
                guard case let .library(.delete(itemID)) = event.change else { continue }
                snapshot.deletedAt[itemID] = max(snapshot.deletedAt[itemID] ?? .distantPast, event.time)
            }
            deletionsKnown = true
        }
        let read = Dictionary(snapshot.articles.compactMap { entry in entry.delivery.map { ($0, entry.deliveredAt) } }, uniquingKeysWith: { first, _ in first })
        let delivered = Dictionary(snapshot.articles.compactMap { entry in
            entry.deliveredAt.map { (entry.material.id, $0) }
        }, uniquingKeysWith: max)
        let deleted = Dictionary(snapshot.deletedAt.map { (Self.deliveryName($0.key), $0.value) }, uniquingKeysWith: max)
        let changed = files.filter { file in
            let changedAt = Self.changeDate(of: file)
            switch read[file.lastPathComponent] {
            case let readAt??: return changedAt.map { $0 != readAt } ?? false
            case .some(nil): return false
            case nil:
                guard let deletedAt = deleted[file.lastPathComponent] else {
                    return Self.isNewDelivery(file, changedAt: changedAt, deliveredAt: delivered, deletedAt: snapshot.deletedAt)
                }
                return changedAt.map { $0 > deletedAt } ?? false
            }
        }
        return (changed, snapshot)
    }

    private static func isNewDelivery(_ file: URL, changedAt: Date?, deliveredAt: [String: Date], deletedAt: [String: Date]) -> Bool {
        guard let head = materialHead(in: file) else {
            return true
        }
        if let removedAt = deletedAt[head.id] {
            return changedAt.map { $0 > removedAt } ?? false
        }
        if let page = head.page, let removedAt = deletedAt["page:\(page)"] {
            return changedAt.map { $0 > removedAt } ?? false
        }
        guard let changedAt, let recorded = deliveredAt[head.id] else {
            return true
        }
        return changedAt > recorded
    }

    private static func materialHead(in archive: URL) -> (id: String, page: String?)? {
        guard let handle = try? FileHandle(forReadingFrom: archive),
              let header = try? handle.read(upToCount: 512), header.count == 512 else { return nil }
        defer { try? handle.close() }
        var digits = ""
        for scalar in String(decoding: header[124..<136], as: UTF8.self).unicodeScalars {
            guard scalar.value >= 48, scalar.value <= 55 else {
                break
            }
            digits.unicodeScalars.append(scalar)
        }
        guard let size = Int(digits, radix: 8), size > 0,
              let data = try? handle.read(upToCount: min(size, 4 * 1024 * 1024)),
              let text = String(data: data, encoding: .utf8),
              let match = text.firstMatch(of: /"id"\s*:\s*("(?:[^"\\]|\\.)*")/),
              let id = try? JSONDecoder().decode(String.self, from: Data(match.1.utf8)) else { return nil }
        var page: String? = nil
        if let url = text[match.range.upperBound...].firstMatch(of: /"sourceURL"\s*:\s*("(?:[^"\\]|\\.)*")/),
           let raw = try? JSONDecoder().decode(String.self, from: Data(url.1.utf8)) {
            page = SourceIndex.key(raw)
        }
        return (id, page)
    }

    private static func changeDate(of file: URL) -> Date? {
        var file = file
        file.removeAllCachedResourceValues()
        return try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

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

    public func holdsMaterialsInApp(_ snapshot: LibrarySnapshot) -> Bool {
        snapshot.articles.contains { $0.delivery == nil }
            || FileManager.default.fileExists(atPath: root.appending(path: "books").path)
            || FileManager.default.fileExists(atPath: root.appending(path: "videos").path)
    }

    private static func deliveryName(_ materialID: String) -> String {
        SHA256.hash(data: Data(materialID.utf8)).map { String(format: "%02x", $0) }.joined() + ".tar"
    }


    public nonisolated func cachedFolder(of entry: ArticleEntry) -> URL {
        cache.appending(path: "articles")
            .appending(path: Self.articleDirectory(root: root, materialID: entry.material.id).lastPathComponent)
            .appending(path: entry.textDigest, directoryHint: .isDirectory)
    }

    public func isUnpacked(_ entry: ArticleEntry) -> Bool {
        FileManager.default.fileExists(atPath: cachedFolder(of: entry).appending(path: Self.textName).path)
    }

    public func deliveryURL(of entry: ArticleEntry) -> URL? {
        guard let cloudFolder, let name = entry.delivery else { return nil }
        return cloudFolder.appending(path: "deliveries").appending(path: name)
    }

    public func openCloudArticle(_ entry: ArticleEntry) throws -> ImportPackage {
        let folder = cachedFolder(of: entry)
        let text = folder.appending(path: Self.textName)
        if !FileManager.default.fileExists(atPath: text.path) {
            guard let archive = deliveryURL(of: entry) else { throw LibraryError.cloudFolderMissing }
            let incoming = folder.appendingPathExtension("incoming")
            try? FileManager.default.removeItem(at: incoming)
            let package = try DeliveryArchive(url: archive).unpack { (_: ImportPackage, path: String) in
                guard let file = Self.contained(path, in: incoming) else { throw LibraryError.escapedPath }
                return file
            }
            try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
            try encoder.encode(package).write(to: incoming.appending(path: Self.textName))
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.moveItem(at: incoming, to: folder)
        }
        let package = try decoder.decode(ImportPackage.self, from: Data(contentsOf: text))
        if !FileManager.default.fileExists(atPath: searchURL(entry.material.id).path) {
            try writeSearchBody(package)
        }
        return package
    }

    public func searchBodies() throws -> [String: SearchBody] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: searchFolder, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var bodies: [String: SearchBody] = [:]
        for file in files where file.pathExtension == "json" {
            guard let body = try? decoder.decode(SearchBody.self, from: Data(contentsOf: file)) else {
                continue
            }
            bodies[body.materialID] = body
        }
        return bodies
    }

    public func removeSearchBody(_ materialID: String) {
        try? FileManager.default.removeItem(at: searchURL(materialID))
    }

    public func hasSearchBody(_ materialID: String) -> Bool {
        FileManager.default.fileExists(atPath: searchURL(materialID).path)
    }

    private func writeSearchBody(_ package: ImportPackage) throws {
        guard package.material.kind == .article || package.material.kind == .book else {
            return
        }
        try FileManager.default.createDirectory(at: searchFolder, withIntermediateDirectories: true)
        try encoder.encode(SearchBody(package)).write(to: searchURL(package.material.id), options: .atomic)
    }

    private func searchURL(_ materialID: String) -> URL {
        searchFolder.appending(path: SHA256.hash(data: Data(materialID.utf8)).map { String(format: "%02x", $0) }.joined() + ".json")
    }


    public func journalFolder() -> URL? {
        cloudFolder?.appending(path: "state", directoryHint: .isDirectory)
    }

    public func appendReadingMode(_ event: ReadingModeEvent, device: String) throws {
        let folder = journalFolder() ?? root
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let line = try JSONLines.line(event, encoder: encoder)
        try JSONLines.append(line, to: folder.appending(path: "\(device).reading.jsonl"))
    }

    public func readingModes(device: String) throws -> [ReadingModeEvent] {
        let folder = journalFolder() ?? root
        let url = folder.appending(path: "\(device).reading.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return text.split(separator: "\n").compactMap { try? decoder.decode(ReadingModeEvent.self, from: Data($0.utf8)) }
    }

    public func loadSync() throws -> JournalKnowledge {
        let url = root.appending(path: "sync.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return JournalKnowledge()
        }
        return try decoder.decode(JournalKnowledge.self, from: Data(contentsOf: url))
    }

    public func saveSync(_ sync: JournalKnowledge) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(sync).write(to: root.appending(path: "sync.json"), options: .atomic)
    }

    public func appendJournal(_ events: [JournalEvent], device: String, compactingAfter limit: Int = 2000) async throws {
        guard let folder = journalFolder(), !events.isEmpty else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let journal = await ownJournal(of: device, in: folder)
        try coordinatedWrite(at: journal, options: .forMerging) { url in
            try JSONLines.append(Data(try self.lines(of: events).utf8), to: url)
        }
        let written = try readJournal(journal)
        guard written.count > limit else { return }
        let generation = folder.appending(path: "\(device).\(Int(Date().timeIntervalSince1970 * 1000)).jsonl")
        let folded = try lines(of: compacted(written))
        try coordinatedWrite(at: generation, options: .forReplacing) { url in try Data(folded.utf8).write(to: url) }
        try coordinatedWrite(at: journal, options: .forDeleting) { url in try FileManager.default.removeItem(at: url) }
    }

    private func ownJournal(of device: String, in folder: URL) async -> URL {
        let files = (try? await CloudFolder.files(in: folder, withExtension: "jsonl")) ?? []
        return files.filter { Self.isAppendJournal($0, of: device) }.max { $0.lastPathComponent < $1.lastPathComponent }
            ?? folder.appending(path: "\(device).jsonl")
    }

    private static func isAppendJournal(_ file: URL, of device: String) -> Bool {
        let name = file.lastPathComponent
        guard file.pathExtension == "jsonl", name.hasPrefix("\(device).") else {
            return false
        }
        if name == "\(device).jsonl" {
            return true
        }
        return name.dropFirst(device.count + 1).dropLast(".jsonl".count).allSatisfy(\.isNumber)
    }

    private static func isJournal(_ file: URL, of device: String) -> Bool {
        file.pathExtension == "jsonl"
            && (file.lastPathComponent == "\(device).jsonl" || file.lastPathComponent.hasPrefix("\(device)."))
    }

    private func lines(of events: [JournalEvent]) throws -> String {
        try events.map { String(decoding: try JSONLines.line($0, encoder: encoder), as: UTF8.self) }.joined()
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

    public func unreadJournalEvents(except device: String, sync: JournalKnowledge, timeout: Duration = .seconds(60)) async throws -> (events: [JournalEvent], applied: [String: Int], waiting: [String]) {
        guard let folder = journalFolder(),
              let files = try? await CloudFolder.files(in: folder, withExtension: "jsonl") else {
            return ([], sync.applied, [])
        }
        let others = files.filter { !Self.isJournal($0, of: device) }
        var applied = sync.applied.filter { name, _ in others.contains { $0.lastPathComponent == name } }
        var events: [JournalEvent] = []
        var waiting: [String] = []
        for file in others {
            let name = file.lastPathComponent
            do {
                try await CloudFolder.download(file, timeout: timeout)
            } catch CloudFolderError.notDownloaded(_, _) {
                waiting.append(name)
                continue
            }
            var text = ""
            do {
                try coordinatedRead(at: file) { url in text = (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
            } catch {
                waiting.append(name)
                continue
            }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            let complete = text.hasSuffix("\n") ? lines.count : max(lines.count - 1, 0)
            var read = applied[name] ?? 0
            for line in lines.dropFirst(read).prefix(max(complete - read, 0)) {
                if let event = try? decoder.decode(JournalEvent.self, from: Data(line.utf8)) {
                    events.append(event)
                }
                read += 1
            }
            applied[name] = read
        }
        return (events, applied, waiting)
    }


    public static func coverFile(root: URL, materialID: String) -> URL {
        root.appending(path: "covers").appending(path: articleDirectory(root: root, materialID: materialID).lastPathComponent)
    }

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

    static func contained(_ path: String, in folder: URL) -> URL? {
        PackagePath.resolves(path, in: folder)
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
