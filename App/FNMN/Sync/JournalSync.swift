import FNMNCore
import Foundation

/// This device's journal and the other devices': the changes waiting to be written to this device's own
/// file, and what it knows of everyone else's. `LibraryModel` sequences the sync; everything about the
/// journals themselves — recording a change, writing this device's, reading the others' and merging them —
/// lives here. What a device knows is `JournalKnowledge`, kept in `sync.json`.
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

    /// What this device knows of the other devices' journals, read with the library.
    func load() async throws {
        known = try await file.loadSync()
    }

    /// A change this device made: it keeps the device's latest word in `known` and waits to be written.
    func record(_ change: JournalEvent.Change) {
        for event in JournalEvent.events(for: change, at: .now) {
            known.record(event)
            pending.append(event)
        }
    }

    /// Writes this device's waiting changes to its journal and saves what it knows; events that did not
    /// reach the file wait for the next write instead of being lost.
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

    /// The folder the other devices' journals live in, once there is one to read.
    func folderToRead() async -> URL? {
        guard let folder = await file.journalFolder() else {
            return nil
        }
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    /// The other devices' changes this device has not taken in yet, with what it knows of them moved on;
    /// nil when there is nothing new to take in.
    func unread() async throws -> [JournalEvent]? {
        let unread = try await file.unreadJournalEvents(except: device, sync: known)
        guard unread.applied != known.applied else {
            return nil
        }
        known.applied = unread.applied
        return unread.events
    }

    /// Applies other devices' changes in time order, keeping this device's latest word in `known`.
    func merging(
        _ events: [JournalEvent], into snapshot: LibrarySnapshot, _ progress: ReadingProgress
    ) -> (catalog: LibrarySnapshot, progress: ReadingProgress) {
        let merged = merge(events, into: snapshot, progress, sync: known)
        known = merged.sync
        return (merged.catalog, merged.progress)
    }

    /// Saves what this device knows of the other devices' journals.
    func save() async throws {
        try await file.saveSync(known)
    }
}
