import Foundation

/// Reading one plate at a time goes through `plates` in order, whatever sections the column has folded: a heading is
/// not a page of its own but stands over the plates of its section.
extension ReaderDocument {
    /// The plate a block is read at: the block itself, or for a heading the first plate after it, or the last plate
    /// when nothing but headings follows. Nil only for a document with no plates.
    public func plate(holding block: Int) -> Int? {
        let next = firstPlate(atOrAfter: block)
        return next < plates.endIndex ? plates[next] : plates.last
    }

    public func plate(after plate: Int) -> Int? {
        let next = firstPlate(atOrAfter: plate + 1)
        return next < plates.endIndex ? plates[next] : nil
    }

    public func plate(before plate: Int) -> Int? {
        let next = firstPlate(atOrAfter: plate)
        return next > 0 ? plates[next - 1] : nil
    }

    /// The plate's place among all of them, from 1; nil for a block that is not a plate.
    public func plateNumber(of plate: Int) -> Int? {
        let index = firstPlate(atOrAfter: plate)
        return index < plates.endIndex && plates[index] == plate ? index + 1 : nil
    }

    /// The headings whose sections hold a block, outermost first, without the title the header already shows: the
    /// block's place in the contents.
    public func headingPath(of block: Int) -> [Int] {
        headings(holding: block).subtracting([repeatedTitle].compactMap(\.self)).sorted()
    }

    /// The position in `plates` of the first plate at or after a block, by halving, since a book has thousands.
    private func firstPlate(atOrAfter block: Int) -> Int {
        var low = plates.startIndex, high = plates.endIndex
        while low < high {
            let middle = (low + high) / 2
            if plates[middle] < block { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
