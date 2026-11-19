import Foundation

public struct DeliveryArchive: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func unpack<Package: Decodable>(
        decoder: JSONDecoder = JSONDecoder(),
        filesInto destination: (Package, String) throws -> URL?
    ) throws -> Package {
        let archive = try FileHandle(forReadingFrom: url)
        defer { try? archive.close() }
        guard let first = try Self.nextEntry(in: archive), first.name == "package.json", first.isFile else {
            throw DeliveryArchiveError.missingPackage
        }
        let package = try decoder.decode(Package.self, from: try Self.read(first.size, from: archive))
        try Self.skipPadding(after: first.size, in: archive)
        while let entry = try Self.nextEntry(in: archive) {
            if entry.isFile, let file = try destination(package, entry.name) {
                try Self.copy(entry.size, from: archive, to: file)
            } else {
                try Self.skip(entry.size, in: archive)
            }
            try Self.skipPadding(after: entry.size, in: archive)
        }
        return package
    }

    public static func write(_ package: ImportPackage, files: [(path: String, source: URL)], to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        let archive = try FileHandle(forWritingTo: url)
        defer { try? archive.close() }
        let text = try JSONEncoder().encode(package)
        try archive.write(contentsOf: try header(name: "package.json", size: text.count))
        try archive.write(contentsOf: text)
        try archive.write(contentsOf: Data(count: (block - text.count % block) % block))
        for (path, source) in files {
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            try archive.write(contentsOf: try header(name: path, size: size))
            let file = try FileHandle(forReadingFrom: source)
            defer { try? file.close() }
            while let part = try file.read(upToCount: chunk), !part.isEmpty {
                try archive.write(contentsOf: part)
            }
            try archive.write(contentsOf: Data(count: (block - size % block) % block))
        }
        try archive.write(contentsOf: Data(count: 2 * block))
    }

    private static func header(name: String, size: Int) throws -> Data {
        let (prefix, short) = try split(name)
        var bytes = [UInt8](repeating: 0, count: block)
        func put(_ text: String, at offset: Int) {
            for (index, byte) in text.utf8.enumerated() { bytes[offset + index] = byte }
        }
        put(short, at: 0)
        put("0000644", at: 100)
        put("0000000", at: 108)
        put("0000000", at: 116)
        put(String(size, radix: 8).leftPadded(to: 11), at: 124)
        put("00000000000", at: 136)
        put("        ", at: 148)
        put("0", at: 156)
        put("ustar", at: 257)
        put("00", at: 263)
        put(prefix, at: 345)
        put(String(bytes.reduce(0) { $0 + Int($1) }, radix: 8).leftPadded(to: 6), at: 148)
        bytes[154] = 0
        return Data(bytes)
    }

    private static func split(_ path: String) throws -> (prefix: String, name: String) {
        if path.utf8.count <= 100 { return ("", path) }
        for slash in path.indices where path[slash] == "/" {
            let prefix = String(path[..<slash])
            let name = String(path[path.index(after: slash)...])
            if prefix.utf8.count <= 155, name.utf8.count <= 100 { return (prefix, name) }
        }
        throw DeliveryArchiveError.pathTooLong(path)
    }

    private struct Entry {
        let name: String
        let size: Int
        let isFile: Bool
    }

    private static let block = 512
    private static let chunk = 64 * 1024

    private static func nextEntry(in archive: FileHandle) throws -> Entry? {
        let header = try read(block, from: archive)
        guard header.contains(where: { $0 != 0 }) else { return nil }
        let bytes = [UInt8](header)
        let name = text(bytes[0..<100])
        let prefix = text(bytes[345..<500])
        guard let size = Int(text(bytes[124..<136]).trimmingCharacters(in: .whitespaces), radix: 8) else {
            throw DeliveryArchiveError.damaged
        }
        switch bytes[156] {
        case UInt8(ascii: "0"), 0:
            return Entry(name: prefix.isEmpty ? name : "\(prefix)/\(name)", size: size, isFile: true)
        case UInt8(ascii: "5"):
            return Entry(name: name, size: size, isFile: false)
        case let kind:
            throw DeliveryArchiveError.unsupportedEntry(String(UnicodeScalar(kind)))
        }
    }

    private static func text(_ field: ArraySlice<UInt8>) -> String {
        String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func read(_ count: Int, from archive: FileHandle) throws -> Data {
        let data = try archive.read(upToCount: count) ?? Data()
        guard data.count == count else { throw DeliveryArchiveError.damaged }
        return data
    }

    private static func copy(_ count: Int, from archive: FileHandle, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
        }
        let file = try FileHandle(forWritingTo: destination)
        defer { try? file.close() }
        var left = count
        while left > 0 {
            let part = try read(min(left, chunk), from: archive)
            try file.write(contentsOf: part)
            left -= part.count
        }
    }

    private static func skip(_ count: Int, in archive: FileHandle) throws {
        try archive.seek(toOffset: try archive.offset() + UInt64(count))
    }

    private static func skipPadding(after size: Int, in archive: FileHandle) throws {
        let padding = (block - size % block) % block
        if padding > 0 { _ = try read(padding, from: archive) }
    }
}

public enum DeliveryArchiveError: Error, Equatable {
    case missingPackage
    case damaged
    case unsupportedEntry(String)
    case pathTooLong(String)
}

private extension String {
    func leftPadded(to width: Int) -> String {
        String(repeating: "0", count: max(width - count, 0)) + self
    }
}

extension DeliveryArchiveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingPackage: "The delivery does not start with its package."
        case .damaged: "The delivery file is cut short or damaged."
        case let .unsupportedEntry(kind): "The delivery holds an entry of an unsupported kind (\(kind))."
        case let .pathTooLong(path): "The file path \(path) is too long for a delivery."
        }
    }
}
