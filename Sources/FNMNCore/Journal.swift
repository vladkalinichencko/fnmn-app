import Foundation

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

    public static func events(for change: Change, at time: Date) -> [JournalEvent] {
        switch change {
        case let .library(.addToAlbum(name, itemIDs)):
            itemIDs.map { JournalEvent(time: time, change: .library(.addToAlbum(name, itemIDs: [$0]))) }
        default:
            [JournalEvent(time: time, change: change)]
        }
    }

    public var key: String? {
        switch change {
        case let .progress(.open(itemID)): "opened:\(itemID)"
        case let .progress(.openGroup(id)): "openedGroup:\(id)"
        case let .progress(.setRead(_, itemID)): "read:\(itemID)"
        case let .progress(.savePosition(_, itemID, _)): "position:\(itemID)"
        case let .progress(.readThrough(_, itemID)): "readThrough:\(itemID)"
        case let .progress(.line(_, itemID)): "line:\(itemID)"
        case let .progress(.fold(_, itemID)): "fold:\(itemID)"
        case let .progress(.reset(itemID)): "reset:\(itemID)"
        case let .library(.setArchived(_, itemID)): "archived:\(itemID)"
        case let .library(.addToAlbum(name, itemIDs)) where itemIDs.count == 1: "placement:\(itemIDs[0]):\(name)"
        case let .library(.removeFromAlbum(name, itemID)): "placement:\(itemID):\(name)"
        case let .library(.removeAnnotation(id)): "removed:\(id)"
        default: nil
        }
    }
}

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

public struct JournalKnowledge: Codable, Equatable, Sendable {
    public var applied: [String: Int] = [:]
    public var clock: [String: Date] = [:]

    public init() {}

    public mutating func record(_ event: JournalEvent) {
        if let key = event.key { clock[key] = max(clock[key] ?? .distantPast, event.time) }
    }
}

public func merge(
    _ events: [JournalEvent], into catalog: LibrarySnapshot, _ progress: ReadingProgress, sync: JournalKnowledge
) -> (catalog: LibrarySnapshot, progress: ReadingProgress, sync: JournalKnowledge) {
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
            if let id = change.annotationID, let removed = sync.clock["removed:\(id)"], event.time <= removed { continue }
            guard let next = try? catalog.applying(change, at: event.time) else { continue }
            progress = next.progressChanges(since: catalog).reduce(progress) { $0.applying($1) }
            catalog = next
        case let .progress(.reset(itemID)):
            let before = progress
            progress = progress.applying(.reset(itemID: itemID), at: event.time)
            func later(_ name: String) -> Bool { (sync.clock["\(name):\(itemID)"] ?? .distantPast) > event.time }
            if later("position") {
                progress.positions[itemID] = before.positions[itemID]
                progress.readings[itemID, default: MaterialReading()].progress = before.readings[itemID]?.progress
            }
            if later("readThrough") { progress.readThrough[itemID] = before.readThrough[itemID] }
            if later("line") { progress.lines[itemID] = before.lines[itemID] }
            if later("opened") { progress.readings[itemID, default: MaterialReading()].openedAt = before.readings[itemID]?.openedAt }
            if later("read") { progress.readings[itemID, default: MaterialReading()].isRead = before.readings[itemID]?.isRead ?? false }
        case let .progress(change):
            if let itemID = change.readingItemID, let reset = sync.clock["reset:\(itemID)"], event.time <= reset { continue }
            progress = progress.applying(change, at: event.time)
        }
    }
    return (catalog, progress, sync)
}

extension LibraryChange {
    fileprivate var annotationID: UUID? {
        switch self {
        case let .mark(_, target), let .unmark(_, target), let .note(_, target):
            Annotation.id(materialID: target.materialID, piece: target.piece)
        default: nil
        }
    }
}

extension ProgressChange {
    fileprivate var readingItemID: String? {
        switch self {
        case let .open(itemID), let .setRead(_, itemID), let .savePosition(_, itemID, _), let .readThrough(_, itemID), let .line(_, itemID): itemID
        case .openGroup, .fold, .reset, .restart, .forget: nil
        }
    }
}
