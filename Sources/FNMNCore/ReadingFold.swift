import Foundation

extension ReaderDocument {
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

    public var lowestHeadings: Set<Int> {
        Set(sections.filter { index, section in
            index != repeatedTitle && section.size > 0
                && !sections.contains { $0.key > index && $0.key < section.end && $0.value.size > 0 }
        }.keys)
    }

    public func headings(holding block: Int) -> Set<Int> {
        Set(sections.filter { $0.key < block && $0.value.end > block }.keys)
    }

    public func headings(endingAbove block: Int) -> Set<Int> {
        Set(sections.filter { $0.key != repeatedTitle && $0.value.end <= block }.keys)
    }

    public func holdsBlocks(_ heading: Int) -> Bool {
        (sections[heading]?.end ?? 0) > heading + 1
    }
}

public func readingPlaceTarget(place: Int?, visible: [Int]) -> Int? {
    guard let place else { return visible.first }
    if visible.contains(place) { return place }
    return visible.last(where: { $0 <= place }) ?? visible.first
}
