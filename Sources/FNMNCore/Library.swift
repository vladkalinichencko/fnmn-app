import Foundation

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var packages: [ImportPackage] = []
    public var books: [BookRecord] = []
    public var positions: [String: ReadingPosition] = [:]
    public var readings: [String: MaterialReading] = [:]
    public var notes: [Note] = []
    public var folders: [String] = []

    public init() {}

    public var continuedID: String? {
        let known = Set(packages.map(\.material.id) + books.map(\.id))
        let opened = readings.compactMap { materialID, reading -> (String, Date)? in
            guard let openedAt = reading.openedAt, known.contains(materialID) else { return nil }
            return (materialID, openedAt)
        }
        if let materialID = opened.max(by: { $0.1 < $1.1 })?.0 { return materialID }
        if let article = packages.first(where: { positions[$0.material.id] != nil }) {
            return article.material.id
        }
        return books.first(where: { positions[$0.id] != nil })?.id
    }

    public var continuedPackage: ImportPackage? {
        packages.first { $0.material.id == continuedID }
    }

    public mutating func importBook(_ record: BookRecord) {
        if let index = books.firstIndex(where: { $0.id == record.id }) {
            books[index] = record
        } else {
            books.append(record)
        }
    }

    public mutating func recordOpening(materialID: String, at date: Date) {
        readings[materialID, default: MaterialReading()].openedAt = date
    }

    public mutating func setRead(_ isRead: Bool, materialID: String) {
        readings[materialID, default: MaterialReading()].isRead = isRead
    }

    public func packages(in folder: String) -> [ImportPackage] {
        packages.filter { $0.folders.contains(folder) }
    }

    public mutating func importPackage(_ package: ImportPackage) throws {
        guard package.version == 1 else { throw LibraryError.unsupportedVersion(package.version) }
        guard !package.blocks.isEmpty else { throw LibraryError.emptyDocument }
        if let index = packages.firstIndex(where: { $0.material.id == package.material.id }) {
            let mergedFolders = Array(Set(packages[index].folders + package.folders)).sorted()
            packages[index] = ImportPackage(material: package.material, sections: package.sections, blocks: package.blocks, folders: mergedFolders)
        } else {
            packages.append(package)
        }
        folders = Array(Set(folders + package.folders)).sorted()
    }

    public mutating func move(materialID: String, to folder: String) {
        guard let index = packages.firstIndex(where: { $0.material.id == materialID }) else { return }
        let names = Array(Set(packages[index].folders + [folder])).sorted()
        let package = packages[index]
        packages[index] = ImportPackage(material: package.material, sections: package.sections, blocks: package.blocks, folders: names)
        folders = Array(Set(folders + [folder])).sorted()
    }

    public mutating func recordVideoTime(materialID: String, blockID: String, seconds: Double) -> Bool {
        if let current = positions[materialID], current.blockID != blockID {
            return false
        }
        positions[materialID] = ReadingPosition(blockID: blockID, videoSeconds: seconds)
        return true
    }
}

public enum LibraryError: Error, Equatable {
    case unsupportedVersion(Int)
    case emptyDocument
}

extension BookError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .missing(name): "Missing \(name)"
        case let .rejected(errors): errors.joined(separator: ", ")
        case let .unsupportedSchema(version): "Unsupported book schema \(version)"
        }
    }
}

public actor LibraryFile {
    private struct UserState: Codable {
        var positions: [String: ReadingPosition]
        var notes: [Note]
        var folders: [String]
        var readings: [String: MaterialReading]
        var books: [BookRecord]

        init(
            positions: [String: ReadingPosition],
            notes: [Note],
            folders: [String],
            readings: [String: MaterialReading],
            books: [BookRecord]
        ) {
            self.positions = positions
            self.notes = notes
            self.folders = folders
            self.readings = readings
            self.books = books
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            positions = try container.decode([String: ReadingPosition].self, forKey: .positions)
            notes = try container.decode([Note].self, forKey: .notes)
            folders = try container.decode([String].self, forKey: .folders)
            readings = try container.decodeIfPresent([String: MaterialReading].self, forKey: .readings) ?? [:]
            books = try container.decodeIfPresent([BookRecord].self, forKey: .books) ?? []
        }
    }

    public nonisolated let root: URL
    private var directory: URL { root }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) {
        root = url
    }

    public func load() throws -> LibrarySnapshot {
        var snapshot = LibrarySnapshot()
        let packagesDirectory = directory.appending(path: "packages")
        if let files = try? FileManager.default.contentsOfDirectory(at: packagesDirectory, includingPropertiesForKeys: nil) {
            snapshot.packages = try files.filter { $0.pathExtension == "json" }.map { try decoder.decode(ImportPackage.self, from: Data(contentsOf: $0)) }
        }
        let stateURL = directory.appending(path: "state.json")
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let state = try decoder.decode(UserState.self, from: Data(contentsOf: stateURL))
            snapshot.positions = state.positions
            snapshot.notes = state.notes
            snapshot.folders = state.folders
            snapshot.readings = state.readings
            snapshot.books = state.books
        }
        return snapshot
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        let packagesDirectory = directory.appending(path: "packages")
        try FileManager.default.createDirectory(at: packagesDirectory, withIntermediateDirectories: true)
        for package in snapshot.packages {
            let name = package.material.id.data(using: .utf8)!.base64EncodedString().replacingOccurrences(of: "/", with: "_")
            try encoder.encode(package).write(to: packagesDirectory.appending(path: "\(name).json"), options: .atomic)
        }
        try saveState(snapshot)
    }

    public func copyBook(from source: URL, named directoryName: String) throws {
        let books = directory.appending(path: "books")
        try FileManager.default.createDirectory(at: books, withIntermediateDirectories: true)
        let destination = books.appending(path: directoryName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func removeBook(named directoryName: String) throws {
        let destination = directory.appending(path: "books").appending(path: directoryName)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    public func installRuntime(from bundle: URL) throws {
        let destination = directory.appending(path: "runtime")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: bundle, to: destination)
    }

    public func saveState(_ snapshot: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = UserState(
            positions: snapshot.positions,
            notes: snapshot.notes,
            folders: snapshot.folders,
            readings: snapshot.readings,
            books: snapshot.books
        )
        try encoder.encode(state).write(to: directory.appending(path: "state.json"), options: .atomic)
    }
}
