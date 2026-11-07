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
    private(set) var seen: Set<String> = []
    private(set) var hidden: Set<String> = []
    var failure: String?
    private let file: DigestFile
    private let device: String
    @ObservationIgnored private var index = DigestIndex()
    @ObservationIgnored private var folder: URL?
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

    /// The digest a post belongs to, for the thread screen and for recording what the reader did with it.
    func digest(of postID: String) -> Digest? {
        digests.first { $0.package.posts.contains { $0.id == postID } }
    }

    func post(_ postID: String) -> DigestPackage.Post? {
        digests.lazy.compactMap { digest in digest.package.posts.first { $0.id == postID } }.first
    }

    /// What this device already has, from the cache; the tab asks once, and the ask is cheap and offline.
    func open() async {
        guard state == .idle else {
            return
        }
        state = .loading
        do {
            index = try await file.loadIndex()
            seen = index.seen
            hidden = index.hidden
            digests = try await file.packages()
            state = .ready
            scoreIfNeeded()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Reads the FNMN folder's digests: what the Mac added since the last sync is downloaded from iCloud,
    /// unpacked, and scored. Called at launch, on returning to the app, and by pull to refresh.
    func sync(folder: URL?) async {
        guard !syncing else {
            return
        }
        syncing = true
        defer { syncing = false }
        if let folder {
            self.folder = folder
        }
        do {
            if let folder {
                try await take(in: folder)
            }
            digests = try await file.packages()
            if state != .ready {
                state = .ready
            }
            scoreIfNeeded()
            await writePending()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// One thing the reader did with a post: kept in the index at once and, on the next sync or when the app
    /// leaves the foreground, in the FNMN folder's journal, which the Mac reads before its next training.
    func record(_ kind: DigestEngagement.Kind, post: DigestPackage.Post, digest: Digest) {
        pending.append(DigestEngagement(kind: kind, postID: post.id, digestID: digest.id))
        switch kind {
        case .opened:
            seen.insert(post.id)
        case .hidden:
            hidden.insert(post.id)
        case .saved:
            break
        }
        scheduleIndexSave()
    }

    /// Writes what is waiting before the app leaves the foreground.
    func settle() async {
        index.seen = seen
        index.hidden = hidden
        try? await file.saveIndex(index)
        indexSave?.cancel()
        await writePending()
    }

    /// The posts of the open digest after the search field's text; an empty query returns them all.
    func posts(matching query: String, in package: DigestPackage) -> [DigestPackage.Post] {
        package.posts(matching: query)
    }

    private func take(in folder: URL) async throws {
        let directory = folder.appending(path: "digests")
        guard CloudFolder.contains(directory) else {
            return
        }
        let tars = try await CloudFolder.files(in: directory, withExtension: "tar")
        let known = Set(index.imported.map(\.file))
        for tar in tars where !known.contains(tar.lastPathComponent) {
            try await CloudFolder.download(tar)
            let digest = try await file.add(tar: tar)
            index.imported.append(.init(file: tar.lastPathComponent, id: digest.id, at: .now))
        }
        if !tars.isEmpty {
            try await file.evict(keeping: 5)
            try await file.saveIndex(index)
        }
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
            self?.labels = scored
        }
    }

    private func scheduleIndexSave() {
        indexSave?.cancel()
        indexSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await self?.saveIndexNow()
        }
    }

    private func saveIndexNow() async {
        index.seen = seen
        index.hidden = hidden
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
