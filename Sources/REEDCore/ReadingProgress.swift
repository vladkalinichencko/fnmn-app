import Foundation

public enum ItemStatus: Equatable, Sendable {
    case unread
    case started
    case read

    public var isRead: Bool {
        self == .read
    }

    public var isStarted: Bool {
        self == .started
    }
}

public struct ReadingProgress: Codable, Equatable, Sendable {
    public var positions: [String: ReadingPosition] = [:]
    public var readThrough: [String: Int] = [:]
    public var readings: [String: MaterialReading] = [:]
    public var folded: [String: [Int]] = [:]
    public var lines: [String: ReadingLine] = [:]
    public var groupsOpened: [String: Date] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        positions = try container.decode([String: ReadingPosition].self, forKey: .positions)
        readThrough = try container.decode([String: Int].self, forKey: .readThrough)
        readings = try container.decode([String: MaterialReading].self, forKey: .readings)
        folded = try container.decodeIfPresent([String: [Int]].self, forKey: .folded) ?? [:]
        lines = try container.decodeIfPresent([String: ReadingLine].self, forKey: .lines) ?? [:]
        groupsOpened = try container.decodeIfPresent([String: Date].self, forKey: .groupsOpened) ?? [:]
    }

    public func applying(_ change: ProgressChange, at date: Date = .now) -> ReadingProgress {
        var next = self
        switch change {
        case let .open(itemID):
            next.readings[itemID, default: MaterialReading()].openedAt = date
        case let .openGroup(id):
            next.groupsOpened[id] = date
        case let .setRead(isRead, itemID):
            next.readings[itemID, default: MaterialReading()].isRead = isRead
        case let .savePosition(position, itemID, progress):
            next.positions[itemID] = position
            next.readings[itemID, default: MaterialReading()].progress = progress
        case let .readThrough(piece, itemID):
            next.readThrough[itemID] = piece
        case let .line(line, itemID):
            next.lines[itemID] = line
        case let .reset(itemID):
            next.positions[itemID] = nil
            next.readThrough[itemID] = nil
            next.lines[itemID] = nil
            next.readings[itemID] = nil
        case let .fold(headings, itemID):
            next.folded[itemID] = headings
        case let .restart(itemID):
            next.positions[itemID] = nil
            next.readThrough[itemID] = nil
            next.lines[itemID] = nil
            next.folded[itemID] = nil
        case let .forget(itemID):
            next.positions[itemID] = nil
            next.readThrough[itemID] = nil
            next.lines[itemID] = nil
            next.folded[itemID] = nil
            next.readings[itemID] = nil
        }
        return next
    }

    public func status(of itemID: String) -> ItemStatus {
        if readings[itemID]?.isRead == true {
            return .read
        }
        if readings[itemID]?.openedAt != nil || positions[itemID] != nil || readThrough[itemID] != nil {
            return .started
        }
        return .unread
    }

    public func isPieceRead(_ piece: Int, of itemID: String, current: Int?) -> Bool {
        if readings[itemID]?.isRead == true { return true }
        if let mark = readThrough[itemID], piece <= mark { return true }
        if let line = lines[itemID], piece < line.piece { return true }
        guard let current else { return false }
        return piece < current
    }

    public func readShare(of piece: Int, in itemID: String, line: ReadingLine) -> Double {
        if readings[itemID]?.isRead == true || piece < line.piece { return 1 }
        return piece == line.piece ? line.fraction : 0
    }

    public func openingPiece(of itemID: String, place: Int?, count: Int) -> Int? {
        if readings[itemID]?.isRead == true { return place }
        let next = readThrough[itemID].map { $0 + 1 }
        guard let first = [place, next].compactMap(\.self).max() else { return nil }
        return min(first, max(count - 1, 0))
    }
}

public enum ProgressChange: Codable, Equatable, Sendable {
    case open(itemID: String)
    case openGroup(id: String)
    case setRead(Bool, itemID: String)
    case savePosition(ReadingPosition, itemID: String, progress: Double)
    case readThrough(piece: Int?, itemID: String)
    case line(ReadingLine?, itemID: String)
    case fold([Int], itemID: String)
    case reset(itemID: String)
    case restart(itemID: String)
    case forget(itemID: String)
}

public struct ReadingLine: Codable, Equatable, Hashable, Sendable {
    public var piece: Int
    public var fraction: Double

    public init(piece: Int, fraction: Double) {
        self.piece = piece
        self.fraction = fraction
    }

    public static func merged(_ lines: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        var merged: [ClosedRange<Double>] = []
        for line in lines.filter({ $0.upperBound > $0.lowerBound }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, line.lowerBound < last.upperBound - 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, line.upperBound)
            } else {
                merged.append(line)
            }
        }
        return merged
    }

    public static func stops(within content: ClosedRange<Double>, lines: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        let edges = [content.lowerBound...content.lowerBound] + lines + [content.upperBound...content.upperBound]
        return zip(edges.indices, edges.indices.dropFirst()).compactMap { above, below in
            let top = edges[above].upperBound, bottom = edges[below].lowerBound
            if bottom - top > 80 { return top + 8...bottom - 8 }
            let middle = (top + bottom) / 2
            return above == 0 || below == edges.count - 1 ? nil : middle...middle
        }
    }

    public static func nearest(to y: Double, in stops: [ClosedRange<Double>]) -> Double? {
        stops.map { min(max(y, $0.lowerBound), $0.upperBound) }.min { abs($0 - y) < abs($1 - y) }
    }
}

extension LibrarySnapshot {
    public func progressChanges(since previous: LibrarySnapshot) -> [ProgressChange] {
        let digests = Dictionary(articles.map { ($0.material.id, $0.textDigest) }, uniquingKeysWith: { $1 })
        var changes: [ProgressChange] = []
        for article in previous.articles {
            let id = article.material.id
            if let digest = digests[id] {
                if digest != article.textDigest { changes.append(.restart(itemID: id)) }
            } else {
                changes.append(.forget(itemID: id))
            }
        }
        return changes
    }

    public func continuedID(_ progress: ReadingProgress) -> String? {
        let known = Set(articles.map(\.material.id))
        let opened = progress.readings.compactMap { materialID, reading -> (String, Date)? in
            guard let openedAt = reading.openedAt, known.contains(materialID), !isArchived(materialID) else {
                return nil
            }
            guard progress.status(of: materialID).isStarted else {
                return nil
            }
            return (materialID, openedAt)
        }
        if let materialID = opened.max(by: { $0.1 < $1.1 })?.0 { return materialID }
        let withPlace = articles.filter { !isArchived($0.material.id) && progress.status(of: $0.material.id).isStarted }
        return withPlace.first { progress.positions[$0.material.id] != nil }?.material.id
    }
}
