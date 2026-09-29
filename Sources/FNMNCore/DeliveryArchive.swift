import Foundation

/// One prepared material as the Mac delivers it: an uncompressed USTAR archive whose first entry is
/// `package.json` and whose other entries are the files its Markdown names, by their relative paths.
/// It is read in one pass with a fixed buffer, so a delivery never sits in memory whole.
public struct DeliveryArchive: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Reads the package, then copies every other entry to the file `destination` names for it.
    public func unpack(filesInto destination: (ImportPackage, String) throws -> URL) throws -> ImportPackage {
        let archive = try FileHandle(forReadingFrom: url)
        defer { try? archive.close() }
        guard let first = try Self.nextEntry(in: archive), first.name == "package.json", first.isFile else {
            throw DeliveryArchiveError.missingPackage
        }
        let package = try JSONDecoder().decode(ImportPackage.self, from: try Self.read(first.size, from: archive))
        try Self.skipPadding(after: first.size, in: archive)
        while let entry = try Self.nextEntry(in: archive) {
            if entry.isFile {
                try Self.copy(entry.size, from: archive, to: try destination(package, entry.name))
            } else {
                _ = try Self.read(entry.size, from: archive)
            }
            try Self.skipPadding(after: entry.size, in: archive)
        }
        return package
    }

    private struct Entry {
        let name: String
        let size: Int
        let isFile: Bool
    }

    private static let block = 512
    private static let chunk = 64 * 1024

    /// The next header, or nil at the two zero blocks that end the archive.
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
            // PAX and GNU long-name headers are not written by the Mac, which fails on a path USTAR cannot hold.
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

    private static func skipPadding(after size: Int, in archive: FileHandle) throws {
        let padding = (block - size % block) % block
        if padding > 0 { _ = try read(padding, from: archive) }
    }
}

public enum DeliveryArchiveError: Error, Equatable {
    case missingPackage
    case damaged
    case unsupportedEntry(String)
}

extension DeliveryArchiveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingPackage: "The delivery does not start with its package."
        case .damaged: "The delivery file is cut short or damaged."
        case let .unsupportedEntry(kind): "The delivery holds an entry of an unsupported kind (\(kind))."
        }
    }
}
