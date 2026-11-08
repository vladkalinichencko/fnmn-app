public struct WebGeneration: Equatable {
    public private(set) var current = 0

    public init() {
    }

    public mutating func next() -> Int {
        current += 1
        return current
    }

    public func accepts(_ reported: Int?) -> Bool {
        reported == current
    }
}
