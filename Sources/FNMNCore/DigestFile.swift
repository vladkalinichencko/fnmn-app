import Foundation

/// The one writer of the digest files: the unpacked digests in the cache, the index of what this device has
/// taken in, and the engagement journal it appends to in the FNMN folder. Digest dates travel as ISO 8601
/// in UTC, so this file owns the decoder and the encoder for them.
public actor DigestFile {
    private let root: URL
    private let cache: URL

    public init(
        url root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "FNMN"),
        cache: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "FNMN")
    ) {
        self.root = root
        self.cache = cache
    }

    /// What this device has taken in; a device that has taken in nothing yet has an empty index.
    public func loadIndex() throws -> DigestIndex {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return DigestIndex()
        }
        return try Self.decoder().decode(DigestIndex.self, from: Data(contentsOf: indexURL))
    }

    public func saveIndex(_ index: DigestIndex) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.encoder().encode(index).write(to: indexURL, options: .atomic)
    }

    /// Unpacks a digest delivery into the cache under the id its package names, replacing an older copy.
    /// The files land in a staging folder first, so a read that stops halfway leaves no half a digest behind.
    public func add(tar: URL) throws -> Digest {
        let staging = cache.appending(path: "digest-staging-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        let package = try DeliveryArchive(url: tar).unpack(decoder: Self.decoder()) { (package: DigestPackage, path: String) throws -> URL? in
            try Self.check(path)
            return staging.appending(path: path)
        }
        let destination = folder(of: package.id)
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: staging, to: destination)
        try Self.encoder().encode(package).write(to: destination.appending(path: "package.json"), options: .atomic)
        return Digest(package: package, folder: destination)
    }

    /// Every unpacked digest, newest window first. A folder without a readable package is a read that stopped
    /// before it wrote one, and the next delivery of the same digest replaces it.
    public func packages() throws -> [Digest] {
        let directory = cache.appending(path: "digests")
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var digests: [Digest] = []
        for folder in folders {
            let packageURL = folder.appending(path: "package.json")
            guard let data = try? Data(contentsOf: packageURL),
                  let package = try? Self.decoder().decode(DigestPackage.self, from: data) else {
                continue
            }
            digests.append(Digest(package: package, folder: folder))
        }
        return digests.sorted { $0.package.window.to > $1.package.window.to }
    }

    /// Removes the unpacked digests beyond the newest `keeping`; the index and what was read stay, so an
    /// evicted digest is not taken in again.
    public func evict(keeping: Int) throws {
        let digests = try packages()
        for digest in digests.dropFirst(keeping) {
            try? FileManager.default.removeItem(at: digest.folder)
        }
    }

    /// Appends one engagement event to this device's journal in the FNMN folder, one JSON object per line.
    public func append(_ engagement: DigestEngagement, device: String, to folder: URL) throws {
        let state = folder.appending(path: "digest-state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        var line = try Self.encoder().encode(engagement)
        line.append(Data("\n".utf8))
        let file = state.appending(path: "\(device).jsonl")
        guard FileManager.default.fileExists(atPath: file.path) else {
            try line.write(to: file, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    private var indexURL: URL {
        root.appending(path: "digests.json")
    }

    private func folder(of id: String) -> URL {
        cache.appending(path: "digests").appending(path: Self.name(of: id))
    }

    /// A digest id names a folder, so the slash of a timestamp is written as a dash.
    private static func name(of id: String) -> String {
        id.replacingOccurrences(of: "/", with: "-")
    }

    /// A delivery names its files by relative paths; a name that climbs out of the digest's folder is refused.
    private static func check(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !parts.contains(".."), !path.isEmpty else {
            throw DigestFileError.unsafePath(path)
        }
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public enum DigestFileError: Error, Equatable, LocalizedError {
    case unsafePath(String)

    public var errorDescription: String? {
        switch self {
        case let .unsafePath(path): "The digest names a file outside its folder (\(path))."
        }
    }
}
