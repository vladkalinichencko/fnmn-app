import FNMNCore
import Foundation

enum SyncStep: Equatable {
    case flush
    case journals
    case catalog
    case deliveries

    var label: String {
        switch self {
        case .flush: "saving changes"
        case .journals: "reading journals"
        case .catalog: "reading the catalog"
        case .deliveries: "reading deliveries"
        }
    }
}

enum SyncState: Equatable {
    case idle
    case syncing(step: SyncStep, pending: Int)
    case finished(pending: Int)
    case failed(String)
}

enum SyncEvent: Equatable {
    case begin
    case stageSucceeded(pending: Int)
    case failed(String)
}

func librarySyncReduce(_ state: SyncState, _ event: SyncEvent) -> SyncState {
    switch (state, event) {
    case (.idle, .begin), (.finished, .begin), (.failed, .begin):
        .syncing(step: .flush, pending: 0)
    case let (.syncing(step, pending), .stageSucceeded(found)):
        switch step {
        case .flush: .syncing(step: .journals, pending: pending + found)
        case .journals: .syncing(step: .catalog, pending: pending + found)
        case .catalog: .syncing(step: .deliveries, pending: pending + found)
        case .deliveries: .finished(pending: pending + found)
        }
    case let (.syncing(_, _), .failed(message)):
        .failed(message)
    default:
        state
    }
}

@MainActor
final class LibrarySync {
    struct Host {
        let cloudFolder: URL?
        let write: LibraryImporter.Write
        let progress: () -> ReadingProgress
        let setProgress: (ReadingProgress) -> Void
        let saveProgress: () async -> Void
    }

    private let journal: JournalSync
    private let importer: LibraryImporter
    private let file: LibraryFile

    init(journal: JournalSync, importer: LibraryImporter, file: LibraryFile) {
        self.journal = journal
        self.importer = importer
        self.file = file
    }

    func run(host: Host) async -> SyncState {
        var state = librarySyncReduce(.idle, .begin)
        while case let .syncing(step, _) = state {
            do {
                let found = try await perform(step, host: host)
                state = librarySyncReduce(state, .stageSucceeded(pending: found))
            } catch {
                state = librarySyncReduce(state, .failed("\(step.label): \(error.localizedDescription)"))
            }
        }
        return state
    }

    private func perform(_ step: SyncStep, host: Host) async throws -> Int {
        switch step {
        case .flush:
            try await journal.flush()
            return 0
        case .journals:
            return try await readJournals(host: host)
        case .catalog:
            return try await readCatalog(host: host)
        case .deliveries:
            return try await readDeliveries(host: host)
        }
    }

    private func readJournals(host: Host) async throws -> Int {
        guard let folder = await journal.folderToRead() else {
            return 0
        }
        do {
            try await CloudFolder.download(folder, timeout: .seconds(60))
        } catch CloudFolderError.notDownloaded {
            return 1
        }
        await host.saveProgress()
        let read = try await journal.pendingRead()
        var merged: (catalog: LibrarySnapshot, progress: ReadingProgress, sync: JournalKnowledge)?
        if !read.events.isEmpty {
            try await host.write(true) { snapshot in
                let result = self.journal.merging(read.events, into: snapshot, host.progress())
                merged = result
                return result.catalog
            }
            if let merged {
                host.setProgress(merged.progress)
                try await file.saveProgress(merged.progress)
                journal.commit(merged.sync, applied: read.applied)
                try await journal.save()
            }
        } else {
            journal.commit(applied: read.applied)
        }
        return read.waiting.count
    }

    private func readCatalog(host: Host) async throws -> Int {
        do {
            _ = try await importer.refreshCatalog(in: host.cloudFolder, write: host.write)
            return 0
        } catch let error as CloudFolderError {
            guard case .notDownloaded = error else {
                throw error
            }
            return 1
        }
    }

    private func readDeliveries(host: Host) async throws -> Int {
        let pending = try await importer.readChangedDeliveries(in: host.cloudFolder, write: host.write)
        return pending.count
    }
}
