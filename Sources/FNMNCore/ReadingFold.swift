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

    /// The headings of the lowest level in each branch: those with text under them and no heading beneath. Closing
    /// them hides only the paragraphs, so every heading of every level stays on the page as the contents.
    /// The title the header shows is not one.
    public var lowestHeadings: Set<Int> {
        Set(sections.filter { index, section in
            index != repeatedTitle && section.size > 0 && section.size == section.end - index - 1
        }.keys)
    }

    /// The headings whose sections contain this block, so the block stays on the page when they are open.
    public func headings(holding block: Int) -> Set<Int> {
        Set(sections.filter { $0.key < block && $0.value.end > block }.keys)
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
