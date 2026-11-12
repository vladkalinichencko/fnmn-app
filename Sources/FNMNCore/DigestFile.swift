import Foundation

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

    public func add(tar: URL) throws -> Digest {
        let staging = cache.appending(path: "digest-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let package = try DeliveryArchive(url: tar).unpack(decoder: Self.decoder()) { (package: DigestPackage, path: String) throws -> URL? in
            try Self.check(path)
            return staging.appending(path: path)
        }
        try Self.check(package)
        let destination = folder(of: package.id)
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: staging, to: destination)
        try Self.encoder().encode(package).write(to: destination.appending(path: "package.json"), options: .atomic)
        return Digest(package: package, folder: destination)
    }

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

    public func evict(keeping: Int) throws {
        let digests = try packages()
        for digest in digests.dropFirst(keeping) {
            try? FileManager.default.removeItem(at: digest.folder)
        }
    }

    public func saveMedia(_ data: Data, as name: String, of digest: Digest) throws -> String {
        let path = "media/\(name)"
        try Self.check(path)
        let file = digest.url(of: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return path
    }

    private var indexURL: URL {
        root.appending(path: "digests.json")
    }

    private func folder(of id: String) -> URL {
        cache.appending(path: "digests").appending(path: Self.name(of: id))
    }

    private static func name(of id: String) -> String {
        id.replacingOccurrences(of: "/", with: "-")
    }

    private static func check(_ package: DigestPackage) throws {
        guard package.schema == DigestPackage.supportedSchema else {
            throw DigestFileError.unsupportedSchema(package.schema)
        }
        let id = package.id
        guard !id.isEmpty, id != ".", id != "..", !id.hasPrefix("/"), !id.contains("\\") else {
            throw DigestFileError.unsafeID(id)
        }
    }

    private static func check(_ path: String) throws {
        guard PackagePath.isSafe(path) else {
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
    case unsafeID(String)
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case let .unsafePath(path): "The digest names a file outside its folder (\(path))."
        case let .unsafeID(id): "The digest names an id that cannot be a folder (\(id))."
        case let .unsupportedSchema(schema): "The digest uses schema \(schema); this app reads schema \(DigestPackage.supportedSchema)."
        }
    }
}
