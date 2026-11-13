import FNMNCore
import Foundation

struct JournalRead {
    let events: [JournalEvent]
    let applied: [String: Int]
    let waiting: [String]
}

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
            try await persist()
        } catch {
            pending = events + pending
            throw error
        }
    }

    func folderToRead() async -> URL? {
        guard let folder = await file.journalFolder() else {
            return nil
        }
        return CloudFolder.contains(folder) ? folder : nil
    }

    func pendingRead() async throws -> JournalRead {
        let unread = try await file.unreadJournalEvents(except: device, sync: known)
        return JournalRead(events: unread.events, applied: unread.applied, waiting: unread.waiting)
    }

    func merging(
        _ events: [JournalEvent], into snapshot: LibrarySnapshot, _ progress: ReadingProgress
    ) -> (catalog: LibrarySnapshot, progress: ReadingProgress, sync: JournalKnowledge) {
        merge(events, into: snapshot, progress, sync: known)
    }

    func commit(_ sync: JournalKnowledge? = nil, applied: [String: Int]) {
        known.applied = applied
        for (key, date) in sync?.clock ?? [:] {
            known.clock[key] = max(known.clock[key] ?? .distantPast, date)
        }
    }

    func save() async throws {
        try await persist()
    }

    private func persist() async throws {
        try await file.saveSync(known)
    }

    func logState() {
        SyncLog.library.log("Journal device: \(self.device, privacy: .public); unwritten events: \(self.pending.count, privacy: .public); read offsets: \(self.known.applied, privacy: .public); event clocks: \(self.known.clock, privacy: .public)")
    }
}
