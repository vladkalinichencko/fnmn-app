import FNMNCore
import Foundation
import Observation
import SwiftUI

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
    private(set) var lastError: String?
    private(set) var pendingDownloads: [URL] = []
    @ObservationIgnored var magazineScrollPosition = ScrollPosition(idType: Never.self)
    private(set) var deliveryFailed = false
    private let file: DigestFile
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var indexSave: Task<Void, Never>?
    @ObservationIgnored private var syncAgain = false

    init(file: DigestFile = DigestFile()) {
        self.file = file
    }

    var current: Digest? {
        digests.first
    }

    var folded: Set<DigestFold> {
        index.folded
    }

    func digest(of postID: String) -> Digest? {
        digests.first { $0.package.posts.contains { $0.id == postID } }
    }

    func post(_ postID: String) -> DigestPackage.Post? {
        digests.lazy.compactMap { digest in digest.package.posts.first { $0.id == postID } }.first
    }

    func contextPost(_ postID: String) -> DigestPackage.Post.ContextPost? {
        digests.lazy
            .flatMap { $0.package.posts }
            .compactMap { $0.context?.post }
            .first { $0.id == postID }
    }

    func sync(folder: URL?) async {
        guard syncState == .idle else {
            syncAgain = true
            return
        }
        syncState = .syncing
        defer {
            syncState = .idle
            if syncAgain {
                syncAgain = false
                Task { await sync(folder: folder) }
            }
        }
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
