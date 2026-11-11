import FNMNCore
import Foundation

@MainActor
final class JournalSync {
    private var known = JournalKnowledge()
    private var pending: [JournalEvent] = []
    private let file: LibraryFile
    let device: String

    init(file: LibraryFile) {
        self.file = file
        if let id = UserDefaults.standard.string(forKey: "deviceID") {
            device = id
            return
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "deviceID")
        device = id
    }

    func load() async throws {
        known = try await file.loadSync()
    }

    func record(_ change: JournalEvent.Change) {
        for event in JournalEvent.events(for: change, at: .now) {
            known.record(event)
            pending.append(event)
        }
    }

    func flush() async throws {
        let events = pending
        pending = []
        do {
            try await file.appendJournal(events, device: device)
            try await file.saveSync(known)
        } catch {
            pending = events + pending
            throw error
        }
    }

    func folderToRead() async -> URL? {
        guard let folder = await file.journalFolder() else {
            return nil
        }
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    func unread() async throws -> [JournalEvent]? {
        let unread = try await file.unreadJournalEvents(except: device, sync: known)
        guard unread.applied != known.applied else {
            return nil
        }
        known.applied = unread.applied
        return unread.events
    }

    func merging(
        _ events: [JournalEvent], into snapshot: LibrarySnapshot, _ progress: ReadingProgress
    ) -> (catalog: LibrarySnapshot, progress: ReadingProgress) {
        let merged = merge(events, into: snapshot, progress, sync: known)
        known = merged.sync
        return (merged.catalog, merged.progress)
    }

    func save() async throws {
        try await file.saveSync(known)
    }

    func logState() {
        SyncLog.library.log("Journal device: \(self.device, privacy: .public); unwritten events: \(self.pending.count, privacy: .public); read offsets: \(self.known.applied, privacy: .public); event clocks: \(self.known.clock, privacy: .public)")
    }
}
