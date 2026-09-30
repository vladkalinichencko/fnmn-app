import Foundation

public enum ReadingFold: Equatable, Sendable {
    case open
    case headings(through: Int)
}

public func readingFoldPinchIn(_ fold: ReadingFold, blocks: [DocumentBlock]) -> ReadingFold {
    let levels = blocks.compactMap(headingLevel)
    guard let deepest = levels.max(), let shallowest = levels.min() else { return .open }
    switch fold {
    case .open:
        return .headings(through: deepest)
    case let .headings(through):
        return .headings(through: max(shallowest, through - 1))
    }
}

public func readingFoldPinchOut(_ fold: ReadingFold, blocks: [DocumentBlock]) -> ReadingFold {
    guard let deepest = blocks.compactMap(headingLevel).max() else { return .open }
    switch fold {
    case .open:
        return .open
    case let .headings(through) where through >= deepest:
        return .open
    case let .headings(through):
        return .headings(through: through + 1)
    }
}

public func visiblePieceIndexes(in blocks: [DocumentBlock], fold: ReadingFold) -> [Int] {
    switch fold {
    case .open:
        return Array(blocks.indices)
    case let .headings(through):
        return blocks.indices.filter { index in
            guard let level = headingLevel(blocks[index]) else { return false }
            return level <= through
        }
    }
}

/// The blocks the next pinch in takes off the page.
public func readingFoldLeaving(_ fold: ReadingFold, blocks: [DocumentBlock]) -> Set<Int> {
    Set(visiblePieceIndexes(in: blocks, fold: fold))
        .subtracting(visiblePieceIndexes(in: blocks, fold: readingFoldPinchIn(fold, blocks: blocks)))
}

/// The blocks the next pinch out brings back onto the page.
public func readingFoldArriving(_ fold: ReadingFold, blocks: [DocumentBlock]) -> Set<Int> {
    Set(visiblePieceIndexes(in: blocks, fold: readingFoldPinchOut(fold, blocks: blocks)))
        .subtracting(visiblePieceIndexes(in: blocks, fold: fold))
}

/// The fold two fingers leave when they let go at this scale: a step in below 0.9, a step out above 1.1.
public func readingFoldPinched(_ fold: ReadingFold, scale: Double, blocks: [DocumentBlock]) -> ReadingFold {
    if scale < 0.9 { return readingFoldPinchIn(fold, blocks: blocks) }
    if scale > 1.1 { return readingFoldPinchOut(fold, blocks: blocks) }
    return fold
}

public func readingPlaceTarget(place: Int?, visible: [Int]) -> Int? {
    guard let place else { return visible.first }
    if visible.contains(place) { return place }
    return visible.last(where: { $0 <= place }) ?? visible.first
}

private func headingLevel(_ block: DocumentBlock) -> Int? {
    guard case let .heading(level, _) = block else { return nil }
    return level
}
