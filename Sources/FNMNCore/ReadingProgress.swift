import Foundation

/// Where the reader is in each material. It changes at every paragraph, so it lives apart from the catalog
/// and is saved in its own file. Only `applying(_:)` changes it.
public struct ReadingProgress: Codable, Equatable, Sendable {
    public var positions: [String: ReadingPosition] = [:]
    public var readThrough: [String: Int] = [:]
    public var readings: [String: MaterialReading] = [:]

    public init() {}

    public func applying(_ change: ProgressChange, at date: Date = .now) -> ReadingProgress {
        var next = self
        switch change {
        case let .open(itemID):
            next.readings[itemID, default: MaterialReading()].openedAt = date
        case let .setRead(isRead, itemID):
            next.readings[itemID, default: MaterialReading()].isRead = isRead
        case let .savePosition(position, itemID, progress):
            next.positions[itemID] = position
            next.readings[itemID, default: MaterialReading()].progress = progress
        case let .readThrough(piece, itemID):
            next.readThrough[itemID] = piece
        case let .restart(itemID):
            next.positions[itemID] = nil
            next.readThrough[itemID] = nil
        case let .forget(itemID):
            next.positions[itemID] = nil
            next.readThrough[itemID] = nil
            next.readings[itemID] = nil
        }
        return next
    }

    /// A paragraph is read when it scrolled past the top, or when it lies at or before the reader's "read through here" mark.
    public func isPieceRead(_ piece: Int, of itemID: String, current: Int?) -> Bool {
        if let mark = readThrough[itemID], piece <= mark { return true }
        guard let current else { return false }
        return piece < current
    }
}

/// Every change to reading progress. A new change is a new case here and one branch in `applying`.
public enum ProgressChange: Equatable, Sendable {
    case open(itemID: String)
    case setRead(Bool, itemID: String)
    case savePosition(ReadingPosition, itemID: String, progress: Double)
    case readThrough(piece: Int?, itemID: String)
    /// The material's text was replaced: its place and "read through here" point nowhere now.
    case restart(itemID: String)
    /// The material left the library.
    case forget(itemID: String)
}

extension LibrarySnapshot {
    /// What reading progress loses when the catalog goes from `previous` to this one: a material that is gone
    /// is forgotten, and one whose text was replaced starts over.
    public func progressChanges(since previous: LibrarySnapshot) -> [ProgressChange] {
        let packages = Dictionary(self.packages.map { ($0.material.id, $0) }, uniquingKeysWith: { $1 })
        let books = Dictionary(self.books.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        var changes: [ProgressChange] = []
        for package in previous.packages {
            let id = package.material.id
            if let current = packages[id] {
                if current.body != package.body || current.blocks != package.blocks { changes.append(.restart(itemID: id)) }
            } else {
                changes.append(.forget(itemID: id))
            }
        }
        for book in previous.books {
            if let current = books[book.id] {
                if current != book { changes.append(.restart(itemID: book.id)) }
            } else {
                changes.append(.forget(itemID: book.id))
            }
        }
        for id in previous.linkIDs.subtracting(linkIDs) {
            changes.append(.forget(itemID: id))
        }
        return changes
    }

    /// The material the reader opened last, or else the first one with a saved place.
    public func continuedID(_ progress: ReadingProgress) -> String? {
        let known = Set(packages.map(\.material.id) + books.map(\.id))
        let opened = progress.readings.compactMap { materialID, reading -> (String, Date)? in
            guard let openedAt = reading.openedAt, known.contains(materialID), !isArchived(materialID) else { return nil }
            return (materialID, openedAt)
        }
        if let materialID = opened.max(by: { $0.1 < $1.1 })?.0 { return materialID }
        if let article = packages.first(where: { progress.positions[$0.material.id] != nil }) {
            return article.material.id
        }
        return books.first(where: { progress.positions[$0.id] != nil })?.id
    }

    private var linkIDs: Set<String> {
        Set((browserCatalog?.sources ?? []).flatMap { $0.materials.map { Self.linkID($0.url) } })
    }
}
