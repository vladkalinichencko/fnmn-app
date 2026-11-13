import FNMNCore
import Foundation
import Observation

enum DigestSyncState: Equatable {
    case idle
    case syncing
}

@MainActor @Observable
final class DigestModel {
    private(set) var state = LoadState.idle
    private(set) var syncState = DigestSyncState.idle
    private(set) var digests: [Digest] = []
    private(set) var index = DigestIndex()
    private(set) var refreshed: [String: [DigestPackage.Post.Media]] = [:]
    private(set) var refreshing: Set<String> = []
    private(set) var lastError: String?
    private(set) var pendingDownloads: [URL] = []
    private(set) var deliveryFailed = false
    private let file: DigestFile
    private let server: ServerLink?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var indexSave: Task<Void, Never>?

    init(file: DigestFile = DigestFile(), server: ServerLink? = nil) {
        self.file = file
        self.server = server
    }

    var current: Digest? {
        digests.first
    }

    var hidden: Set<String> {
        index.hidden
    }

    var folded: Set<DigestFold> {
        index.folded
    }

    func media(for post: DigestPackage.Post) -> [DigestPackage.Post.Media] {
        refreshed[post.id] ?? post.media
    }

    func refresh(_ post: DigestPackage.Post, digest: Digest) async {
        guard let server else {
            lastError = "Set up the Mac server to fetch this picture again."
            return
        }
        guard !refreshing.contains(post.id) else {
            return
        }
        do {
            let connection = try server.configured()
            refreshing.insert(post.id)
            defer { refreshing.remove(post.id) }
            let media = try await server.port.refreshDigestPost(post.id, connection: connection)
            var local: [DigestPackage.Post.Media] = []
            for item in media {
                let name = (item.path as NSString).lastPathComponent
                let data = try await server.port.digestMedia(name, connection: connection)
                let path = try await file.saveMedia(data, as: "refresh-\(name)", of: digest)
                local.append(.init(path: path, width: item.width, height: item.height))
            }
            refreshed[post.id] = local
        } catch {
            lastError = error.localizedDescription
        }
    }

    func digest(of postID: String) -> Digest? {
        digests.first { $0.package.posts.contains { $0.id == postID } }
    }

    func post(_ postID: String) -> DigestPackage.Post? {
        digests.lazy.compactMap { digest in digest.package.posts.first { $0.id == postID } }.first
    }

    func sync(folder: URL?) async {
        guard syncState == .idle else {
            return
        }
        syncState = .syncing
        defer { syncState = .idle }
        if state == .idle {
            state = .loading
        }
        do {
            try await load()
            digests = try await file.packages()
            pendingDownloads = []
            deliveryFailed = false
            if let folder {
                let taken = await take(in: folder)
                lastError = taken.failures.isEmpty ? nil : taken.failures.joined(separator: "; ")
                pendingDownloads = taken.pending
                deliveryFailed = !taken.failures.isEmpty
                if taken.took {
                    digests = try await file.packages()
                }
            }
            state = .ready
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

    func hide(_ post: DigestPackage.Post) {
        index.hidden.insert(post.id)
        scheduleIndexSave()
    }

    func toggleFold(_ fold: DigestFold) {
        if index.folded.remove(fold) == nil {
            index.folded.insert(fold)
        }
        scheduleIndexSave()
    }

    func settle() async {
        try? await file.saveIndex(index)
        indexSave?.cancel()
    }

    private func load() async throws {
        guard !loaded else {
            return
        }
        index = try await file.loadIndex()
        loaded = true
    }

    private func take(in folder: URL) async -> (failures: [String], pending: [URL], took: Bool) {
        let target = DigestDeliveries(file: file, index: index, unpacked: Set(digests.map(\.id)))
        let result = await DeliverySync.run(target, in: folder)
        index = target.index
        return (result.failures, result.pending, target.took)
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
}

@MainActor
private final class DigestDeliveries: DeliveryTarget {
    let subfolder = "digests"
    private let file: DigestFile
    private var unpacked: Set<String>
    private var imported: [String: String]
    private(set) var took = false
    var index: DigestIndex

    init(file: DigestFile, index: DigestIndex, unpacked: Set<String>) {
        self.file = file
        self.index = index
        self.unpacked = unpacked
        imported = Dictionary(index.imported.map { ($0.file, $0.id) }, uniquingKeysWith: { first, _ in first })
    }

    func changed(_ archives: [URL]) async throws -> [URL] {
        archives.filter { archive in
            guard let id = imported[archive.lastPathComponent] else {
                return true
            }
            return !unpacked.contains(id)
        }
    }

    func add(_ archive: URL, index: Int, total: Int) async throws {
        let digest = try await file.add(tar: archive)
        took = true
        unpacked.insert(digest.id)
        if imported.updateValue(digest.id, forKey: archive.lastPathComponent) == nil {
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
