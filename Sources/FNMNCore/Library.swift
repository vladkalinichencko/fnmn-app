import Foundation

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var packages: [ImportPackage] = []
    public var positions: [String: ReadingPosition] = [:]
    public var notes: [Note] = []
    public var folders: [String] = []

    public init() {}

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

public actor LibraryFile {
    private struct UserState: Codable {
        var positions: [String: ReadingPosition]
        var notes: [Note]
        var folders: [String]
    }

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) {
        directory = url
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

    public func saveState(_ snapshot: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = UserState(positions: snapshot.positions, notes: snapshot.notes, folders: snapshot.folders)
        try encoder.encode(state).write(to: directory.appending(path: "state.json"), options: .atomic)
    }
}
