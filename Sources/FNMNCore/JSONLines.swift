import Foundation

/// A file of one JSON object per line, appended. The library's journal and the digest's engagement are both this.
enum JSONLines {
    /// The value's line, newline included.
    static func line<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> Data {
        var line = try encoder.encode(value)
        line.append(Data("\n".utf8))
        return line
    }

    /// Appends to the file, making it when it is not there.
    static func append(_ line: Data, to file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else {
            try line.write(to: file, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
