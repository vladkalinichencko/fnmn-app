import Foundation

public enum ReadingFold: Equatable, Sendable {
    case open
    case headings(through: Int)
}

public func readingFoldPinchIn(_ fold: ReadingFold, pieces: [ArticlePiece]) -> ReadingFold {
    let levels = pieces.compactMap(headingLevel)
    guard let deepest = levels.max(), let shallowest = levels.min() else { return .open }
    switch fold {
    case .open:
        return .headings(through: deepest)
    case let .headings(through):
        return .headings(through: max(shallowest, through - 1))
    }
}

public func readingFoldPinchOut(_ fold: ReadingFold, pieces: [ArticlePiece]) -> ReadingFold {
    guard let deepest = pieces.compactMap(headingLevel).max() else { return .open }
    switch fold {
    case .open:
        return .open
    case let .headings(through) where through >= deepest:
        return .open
    case let .headings(through):
        return .headings(through: through + 1)
    }
}

public func visiblePieceIndexes(in pieces: [ArticlePiece], fold: ReadingFold) -> [Int] {
    switch fold {
    case .open:
        return Array(pieces.indices)
    case let .headings(through):
        return pieces.indices.filter { index in
            guard let level = headingLevel(pieces[index]) else { return false }
            return level <= through
        }
    }
}

public func readingPlaceTarget(place: Int?, visible: [Int]) -> Int? {
    guard let place else { return visible.first }
    if visible.contains(place) { return place }
    return visible.last(where: { $0 <= place }) ?? visible.first
}

private func headingLevel(_ piece: ArticlePiece) -> Int? {
    guard case let .paragraph(runs) = piece else { return nil }
    return ArticleBody.heading(runs)?.level
}
