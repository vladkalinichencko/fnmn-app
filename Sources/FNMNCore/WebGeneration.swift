/// Every load of a web page gets a generation, and the page reports it with each message. A message that names an
/// older generation comes from a page the app has already replaced, so writing its result would describe the wrong page.
public struct WebGeneration: Equatable {
    public private(set) var current = 0

    public init() {
    }

    /// Starts a new page and returns the number that page must report back.
    public mutating func next() -> Int {
        current += 1
        return current
    }

    /// A message that names no generation comes from a page this app did not load.
    public func accepts(_ reported: Int?) -> Bool {
        reported == current
    }
}
