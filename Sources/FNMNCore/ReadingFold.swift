import Foundation

extension ReaderDocument {
    /// The blocks on the page when these headings are folded: a folded heading stays and hides what it holds,
    /// the cover and the title the header already shows are never in the column.
    public func visibleBlocks(folded: Set<Int>) -> [Int] {
        var visible: [Int] = []
        var index = 0
        while index < blocks.count {
            defer { index += 1 }
            if index == repeatedTitle || index == lead { continue }
            visible.append(index)
            if folded.contains(index), let section = sections[index] { index = section.end - 1 }
        }
        return visible
    }

    /// Whether a heading holds anything to fold away.
    public func holdsBlocks(_ heading: Int) -> Bool {
        (sections[heading]?.end ?? 0) > heading + 1
    }
}

public func readingPlaceTarget(place: Int?, visible: [Int]) -> Int? {
    guard let place else { return visible.first }
    if visible.contains(place) { return place }
    return visible.last(where: { $0 <= place }) ?? visible.first
}
