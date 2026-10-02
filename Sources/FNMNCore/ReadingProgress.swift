import Foundation

/// Where the reader is in each material. It changes at every paragraph, so it lives apart from the catalog
/// and is saved in its own file. Only `applying(_:)` changes it.
public struct ReadingProgress: Codable, Equatable, Sendable {
    public var positions: [String: ReadingPosition] = [:]
    public var readThrough: [String: Int] = [:]
    public var readings: [String: MaterialReading] = [:]
    /// The headings a material has closed up. A material without an entry has never been folded by hand,
    /// and opens with every section closed.
    public var folded: [String: [Int]] = [:]
    /// Where each material's reading line stands.
    public var lines: [String: ReadingLine] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        positions = try container.decode([String: ReadingPosition].self, forKey: .positions)
        readThrough = try container.decode([String: Int].self, forKey: .readThrough)
        readings = try container.decode([String: MaterialReading].self, forKey: .readings)
        folded = try container.decodeIfPresent([String: [Int]].self, forKey: .folded) ?? [:]
        lines = try container.decodeIfPresent([String: ReadingLine].self, forKey: .lines) ?? [:]
    }

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

    /// Without the reading line on screen, a paragraph is read when the material is marked read, when it scrolled
    /// past the top, when it lies at or before the reader's "read through here" mark, or above where the line was
    /// left: hiding the line takes nothing read away.
    public func isPieceRead(_ piece: Int, of itemID: String, current: Int?) -> Bool {
        if readings[itemID]?.isRead == true { return true }
        if let mark = readThrough[itemID], piece <= mark { return true }
        if let line = lines[itemID], piece < line.piece { return true }
        guard let current else { return false }
        return piece < current
    }

    /// With the reading line, how much of a block is read, from its top: the blocks above the line's block whole, the
    /// line's own block down to the line, no others. The line moves up as well as down, and the "read through here"
    /// mark, which belongs to reading without it, does not count.
    public func readShare(of piece: Int, in itemID: String, line: ReadingLine) -> Double {
        if readings[itemID]?.isRead == true || piece < line.piece { return 1 }
        return piece == line.piece ? line.fraction : 0
    }

    /// The block a material opens at, put at the top of the screen: the first one not read yet, so reading goes on
    /// from where it was left instead of from the last block read. That is the saved place, or the block after the
    /// "read through here" mark when the mark lies further on. A material marked read keeps its saved place.
    public func openingPiece(of itemID: String, place: Int?, count: Int) -> Int? {
        if readings[itemID]?.isRead == true { return place }
        let next = readThrough[itemID].map { $0 + 1 }
        guard let first = [place, next].compactMap(\.self).max() else { return nil }
        return min(first, max(count - 1, 0))
    }
}

/// Every change to reading progress. A new change is a new case here and one branch in `applying`.
public enum ProgressChange: Codable, Equatable, Sendable {
    case open(itemID: String)
    case setRead(Bool, itemID: String)
    case savePosition(ReadingPosition, itemID: String, progress: Double)
    case readThrough(piece: Int?, itemID: String)
    /// The reading line moved, or was taken away.
    case line(ReadingLine?, itemID: String)
    /// The headings of the material that are closed up, sorted.
    case fold([Int], itemID: String)
    /// The reader starts the material over: the place, the "read through here" mark and everything else
    /// reading recorded are gone, and it leaves Continue.
    case reset(itemID: String)
    /// The material's text was replaced: its place and "read through here" point nowhere now.
    case restart(itemID: String)
    /// The material left the library.
    case forget(itemID: String)
}

/// The line the reader moves down the text as it reads: the text above it is read. It stands in the block whose
/// text it has not passed yet, at a share of that block's height, so it keeps its place between the same lines of
/// text when the column is narrower or the font larger. Above the block, in the gap after the one before, the share
/// is below zero.
public struct ReadingLine: Codable, Equatable, Hashable, Sendable {
    public var piece: Int
    public var fraction: Double

    public init(piece: Int, fraction: Double) {
        self.piece = piece
        self.fraction = fraction
    }

    /// Lines of text given by their top and bottom, top to bottom, with lines that overlap taken as one: cells side by
    /// side in a table, or a formula taller than the line beside it.
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

    /// Where the line may stand among merged lines of text: halfway between two that follow one another, at the top
    /// of the first and at the bottom of the last, and anywhere across a space wider than any between paragraphs,
    /// which holds a picture, a video or a formula that scrolls sideways.
    public static func stops(between lines: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        guard let first = lines.first, let last = lines.last else { return [] }
        let between = zip(lines, lines.dropFirst()).map { above, below -> ClosedRange<Double> in
            let top = above.upperBound, bottom = below.lowerBound
            let middle = (top + bottom) / 2
            return bottom - top > 80 ? top + 8...bottom - 8 : middle...middle
        }
        return [first.lowerBound...first.lowerBound] + between + [last.upperBound...last.upperBound]
    }

    /// Where the line stands at the top of a block whose row starts at `top`: at the stop between the text above the
    /// block and its own first line, the place a drag into the gap between them comes to rest. Over a picture the
    /// stop spans the picture, and the line stands at the block's top.
    public static func stop(atTopOf top: Double, lines: [ClosedRange<Double>], stops: [ClosedRange<Double>]) -> Double {
        guard let below = lines.firstIndex(where: { $0.lowerBound >= top - 1 }), stops.indices.contains(below) else { return top }
        return min(max(top, stops[below].lowerBound), stops[below].upperBound)
    }

    /// The place closest to a height: the height itself across a picture, or else the nearest stop between lines.
    public static func nearest(to y: Double, in stops: [ClosedRange<Double>]) -> Double? {
        stops.map { min(max(y, $0.lowerBound), $0.upperBound) }.min { abs($0 - y) < abs($1 - y) }
    }
}

extension LibrarySnapshot {
    /// What reading progress loses when the catalog goes from `previous` to this one: a material that is gone
    /// is forgotten, and one whose text was replaced starts over.
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

    /// The material the reader opened last, or else the first one with a saved place.
    public func continuedID(_ progress: ReadingProgress) -> String? {
        let known = Set(articles.map(\.material.id))
        let opened = progress.readings.compactMap { materialID, reading -> (String, Date)? in
            guard let openedAt = reading.openedAt, known.contains(materialID), !isArchived(materialID) else { return nil }
            return (materialID, openedAt)
        }
        if let materialID = opened.max(by: { $0.1 < $1.1 })?.0 { return materialID }
        return articles.first(where: { progress.positions[$0.material.id] != nil })?.material.id
    }
}
