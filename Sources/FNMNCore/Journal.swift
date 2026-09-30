import Foundation

/// One change a device made to what the reader keeps: where they are, what they marked, how they sorted.
/// Each device appends its changes to its own file in the FNMN folder, so no two devices ever write the same
/// file, and every device merges all the files by time.
public struct JournalEvent: Codable, Equatable, Sendable {
    public enum Change: Codable, Equatable, Sendable {
        case library(LibraryChange)
        case progress(ProgressChange)
    }

    public let time: Date
    public let change: Change

    public init(time: Date, change: Change) {
        self.time = time
        self.change = change
    }

    /// The events a change becomes in the journal. Adding several materials to an album is one event per
    /// material, so each placement has its own latest word.
    public static func events(for change: Change, at time: Date) -> [JournalEvent] {
        switch change {
        case let .library(.addToAlbum(name, itemIDs)):
            itemIDs.map { JournalEvent(time: time, change: .library(.addToAlbum(name, itemIDs: [$0]))) }
        default:
            [JournalEvent(time: time, change: change)]
        }
    }

    /// What the change sets, where the latest change wins over an older one from another device. A change
    /// that adds to or takes from a collection (marks, albums, deletion) has no key and always applies.
    public var key: String? {
        switch change {
        case let .progress(.open(itemID)): "opened:\(itemID)"
        case let .progress(.setRead(_, itemID)): "read:\(itemID)"
        case let .progress(.savePosition(_, itemID, _)): "position:\(itemID)"
        case let .progress(.readThrough(_, itemID)): "readThrough:\(itemID)"
        case let .library(.setArchived(_, itemID)): "archived:\(itemID)"
        case let .library(.addToAlbum(name, itemIDs)) where itemIDs.count == 1: "placement:\(itemIDs[0]):\(name)"
        case let .library(.removeFromAlbum(name, itemID)): "placement:\(itemID):\(name)"
        default: nil
        }
    }
}

/// A journal folded down: for each key only its latest change stays, and every change without a key stays,
/// in time order. Applying it again from the start gives what applying the whole journal gave.
public func compacted(_ events: [JournalEvent]) -> [JournalEvent] {
    var latest: [String: Int] = [:]
    for (index, event) in events.enumerated() {
        if let key = event.key { latest[key] = index }
    }
    return events.enumerated()
        .filter { index, event in event.key.map { latest[$0] == index } ?? true }
        .map(\.element)
        .sorted { $0.time < $1.time }
}

/// What a device knows of the other devices' journals: how many lines of each it has applied, and when each
/// keyed value last changed, here or anywhere.
public struct JournalSync: Codable, Equatable, Sendable {
    public var applied: [String: Int] = [:]
    public var clock: [String: Date] = [:]

    public init() {}

    /// Records a change made on this device, so an older change from another device does not undo it.
    public mutating func record(_ event: JournalEvent) {
        if let key = event.key { clock[key] = max(clock[key] ?? .distantPast, event.time) }
    }
}

/// Applies other devices' changes in time order. A keyed change older than what this device already has for
/// that key is skipped. A catalog change that no longer applies here, such as renaming an album this device has
/// already deleted, is skipped too; a material that leaves the catalog leaves reading progress with it.
public func merge(
    _ events: [JournalEvent], into catalog: LibrarySnapshot, _ progress: ReadingProgress, sync: JournalSync
) -> (catalog: LibrarySnapshot, progress: ReadingProgress, sync: JournalSync) {
    var catalog = catalog
    var progress = progress
    var sync = sync
    for event in events.sorted(by: { $0.time < $1.time }) {
        if let key = event.key {
            guard (sync.clock[key] ?? .distantPast) < event.time else { continue }
            sync.clock[key] = event.time
        }
        switch event.change {
        case let .library(change):
            guard let next = try? catalog.applying(change, at: event.time) else { continue }
            progress = next.progressChanges(since: catalog).reduce(progress) { $0.applying($1) }
            catalog = next
        case let .progress(change):
            progress = progress.applying(change, at: event.time)
        }
    }
    return (catalog, progress, sync)
}
