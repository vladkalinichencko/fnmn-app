import FNMNCore
import Foundation
import Observation

enum DigestLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

/// The one owner of the social digests on this device: the deliveries the Mac left in the FNMN folder, the
/// digests unpacked in the cache, the topics the classifier gave their posts, and the engagement this device
/// writes back for the Mac's next training. `LibraryModel` owns the folder; this model asks it nothing and
/// receives the folder with every sync.
@MainActor @Observable
final class DigestModel {
    private(set) var state = DigestLoadState.idle
    /// Newest window first.
    private(set) var digests: [Digest] = []
    /// The folder each post's text belongs to, by the model the newest digest carried.
    private(set) var labels: [String: String] = [:]
    /// The one record of what this device read, hid and took in; the views read it through `seen` and `hidden`.
    private(set) var index = DigestIndex()
    /// The last sync's failures, while the magazine it already had stays on screen.
    private(set) var lastError: String?
    private let file: DigestFile
    private let device: String
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var pending: [DigestEngagement] = []
    @ObservationIgnored private var indexSave: Task<Void, Never>?
    @ObservationIgnored private var scoring: Task<Void, Never>?
    @ObservationIgnored private var syncing = false

    init(device: String, file: DigestFile = DigestFile()) {
        self.device = device
        self.file = file
    }

    var current: Digest? {
        digests.first
    }

    var seen: Set<String> {
        index.seen
    }

    var hidden: Set<String> {
        index.hidden
    }

    /// The digest a post belongs to, for the thread screen and for recording what the reader did with it.
    func digest(of postID: String) -> Digest? {
        digests.first { $0.package.posts.contains { $0.id == postID } }
    }

    func post(_ postID: String) -> DigestPackage.Post? {
        digests.lazy.compactMap { digest in digest.package.posts.first { $0.id == postID } }.first
    }

    /// Reads the FNMN folder's digests: what the Mac added since the last sync is downloaded from iCloud,
    /// unpacked, and scored. The only entry: the tab, the launch and the pull all call it; a nil folder reads
    /// what is already in the cache.
    func sync(folder: URL?) async {
        guard !syncing else {
            return
        }
        syncing = true
        defer { syncing = false }
        if state == .idle {
            state = .loading
        }
        if let folder {
            self.folder = folder
        }
        do {
            try await load()
            if let folder {
                let failures = await take(in: folder)
                lastError = failures.isEmpty ? nil : failures.joined(separator: "; ")
            }
            digests = try await file.packages()
            state = .ready
            scoreIfNeeded()
            await writePending()
        } catch is CancellationError {
            if state == .loading {
                state = .idle
            }
        } catch {
            if state == .ready {
                lastError = error.localizedDescription
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// One thing the reader did with a post: kept in the index at once and, on the next sync or when the app
    /// leaves the foreground, in the FNMN folder's journal, which the Mac reads before its next training.
    func record(_ kind: DigestEngagement.Kind, post: DigestPackage.Post, digest: Digest) {
        pending.append(DigestEngagement(kind: kind, postID: post.id, digestID: digest.id))
        switch kind {
        case .opened:
            index.seen.insert(post.id)
        case .hidden:
            index.hidden.insert(post.id)
        case .saved:
            break
        }
        scheduleIndexSave()
    }

    /// The one save path: the engagement is recorded here, so a menu cannot save a post without telling the
    /// Mac's next training about it. Returns the link the library imports.
    func save(_ post: DigestPackage.Post, digest: Digest) -> URL {
        record(.saved, post: post, digest: digest)
        return post.permalink
    }

    /// Writes what is waiting before the app leaves the foreground.
    func settle() async {
        try? await file.saveIndex(index)
        indexSave?.cancel()
        await writePending()
    }

    /// The posts of the open digest after the search field's text, minus the hidden ones.
    func posts(matching query: String, in package: DigestPackage) -> [DigestPackage.Post] {
        package.posts(matching: query, hidden: hidden)
    }

    private func load() async throws {
        guard !loaded else {
            return
        }
        index = try await file.loadIndex()
        digests = try await file.packages()
        loaded = true
    }

    /// Takes the deliveries the index does not hold, and the ones whose unpacked copy the system removed.
    /// One bad delivery is a line of `lastError`; the others still land, and the magazine stays on screen.
    private func take(in folder: URL) async -> [String] {
        let unpacked = Set((try? await file.packages())?.map(\.id) ?? [])
        let target = DigestDeliveries(file: file, index: index, unpacked: unpacked)
        let failures = await DeliverySync.run(target, in: folder)
        index = target.index
        return failures
    }

    private func scoreIfNeeded() {
        scoring?.cancel()
        guard let newest = digests.first, let model = newest.package.model else {
            labels = [:]
            return
        }
        let posts = digests.flatMap { $0.package.posts }
        let url = newest.url(of: model.file)
        scoring = Task { [weak self] in
            let scored = await InterestClassifier.labels(modelURL: url, posts: posts)
            guard !Task.isCancelled else {
                return
            }
            self?.labels = scored.labels
            if let error = scored.error {
                self?.lastError = error
            }
        }
    }

    private func scheduleIndexSave() {
        indexSave?.cancel()
        indexSave = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            await self?.saveIndexNow()
        }
    }

    private func saveIndexNow() async {
        try? await file.saveIndex(index)
    }

    /// Appends the waiting engagement to this device's journal; events that cannot be written wait for the
    /// next sync or the next settling instead of being lost.
    private func writePending() async {
        guard let folder, !pending.isEmpty else {
            return
        }
        let events = pending
        pending = []
        for event in events {
            do {
                try await file.append(event, device: device, to: folder)
            } catch {
                pending = events + pending
                return
            }
        }
    }
}

/// The digest's side of `DeliverySync`: the index and the unpacked folders decide what is known, and every
/// new archive is unpacked and recorded. The index is written once after the loop.
@MainActor
private final class DigestDeliveries: DeliveryTarget {
    let subfolder = "digests"
    private let file: DigestFile
    private var unpacked: Set<String>
    var index: DigestIndex

    init(file: DigestFile, index: DigestIndex, unpacked: Set<String>) {
        self.file = file
        self.index = index
        self.unpacked = unpacked
    }

    func changed(_ archives: [URL]) async throws -> [URL] {
        var imported: [String: String] = [:]
        for entry in index.imported {
            imported[entry.file] = entry.id
        }
        return archives.filter { archive in
            guard let id = imported[archive.lastPathComponent] else {
                return true
            }
            return !unpacked.contains(id)
        }
    }

    func add(_ archive: URL, index: Int, total: Int) async throws {
        let digest = try await file.add(tar: archive)
        unpacked.insert(digest.id)
        if !self.index.imported.contains(where: { $0.file == archive.lastPathComponent }) {
            self.index.imported.append(.init(file: archive.lastPathComponent, id: digest.id, at: .now))
        }
    }

    func finish(_ archives: [URL]) async throws {
        guard !archives.isEmpty else {
            return
        }
        try await file.evict(keeping: 5)
        try await file.saveIndex(index)
    }
}
