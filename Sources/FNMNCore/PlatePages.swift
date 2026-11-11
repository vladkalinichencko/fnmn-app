import Foundation

extension ReaderDocument {
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

    public func plateNumber(of plate: Int) -> Int? {
        let index = firstPlate(atOrAfter: plate)
        return index < plates.endIndex && plates[index] == plate ? index + 1 : nil
    }

    public func headingPath(of block: Int) -> [Int] {
        headings(holding: block).subtracting([repeatedTitle].compactMap(\.self)).sorted()
    }

    private func firstPlate(atOrAfter block: Int) -> Int {
        var low = plates.startIndex, high = plates.endIndex
        while low < high {
            let middle = (low + high) / 2
            if plates[middle] < block { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
