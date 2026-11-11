import Foundation

public enum CloudFolder {
    @concurrent
    public static func download(_ item: URL, timeout: Duration = .seconds(600)) async throws {
        var pending = missing(in: item)
        for file in pending {
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        }
        let deadline = ContinuousClock.now + timeout
        var pause = Duration.milliseconds(500)
        while !pending.isEmpty {
            guard ContinuousClock.now < deadline else { throw CloudFolderError.notDownloaded(count: pending.count) }
            try await Task.sleep(for: pause)
            let still = pending.filter { !isLocal($0) }
            pause = still.count == pending.count ? min(pause * 2, .seconds(5)) : .milliseconds(500)
            pending = still
        }
    }

    public static func contains(_ file: URL) -> Bool {
        FileManager.default.fileExists(atPath: file.path) || FileManager.default.fileExists(atPath: placeholder(of: file).path)
    }

    @concurrent
    public static func archives(in folder: URL?, subfolder: String) async throws -> [URL] {
        guard let folder else {
            return []
        }
        let directory = folder.appending(path: subfolder)
        guard contains(directory) else {
            return []
        }
        return try await files(in: directory, withExtension: "tar")
    }

    @concurrent
    public static func files(in folder: URL, withExtension pathExtension: String? = nil) async throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .map(downloadedName)
            .filter { pathExtension == nil ? !$0.lastPathComponent.hasPrefix(".") : $0.pathExtension == pathExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func missing(in item: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return isLocal(item) ? [] : [item]
        }
        let keys: [URLResourceKey] = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let walk = FileManager.default.enumerator(at: item, includingPropertiesForKeys: keys) else { return [] }
        return walk.compactMap { $0 as? URL }.compactMap { url in
            let name = downloadedName(url)
            if name != url { return name }
            return isLocal(url) ? nil : url
        }
    }

    private static func downloadedName(_ url: URL) -> URL {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return url }
        return url.deletingLastPathComponent().appending(path: String(name.dropFirst().dropLast(".icloud".count)))
    }

    private static func placeholder(of file: URL) -> URL {
        file.deletingLastPathComponent().appending(path: ".\(file.lastPathComponent).icloud")
    }

    public static func isLocal(_ url: URL) -> Bool {
        var url = url
        url.removeAllCachedResourceValues()
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard values?.isUbiquitousItem == true else { return FileManager.default.fileExists(atPath: url.path) }
        return values?.ubiquitousItemDownloadingStatus == .current
    }
}

public enum CloudFolderError: LocalizedError {
    case notDownloaded(count: Int, name: String? = nil)

    public var errorDescription: String? {
        switch self {
        case let .notDownloaded(count, name):
            if let name {
                return "“\(name)” is still downloading from iCloud. Try again when it is on this device."
            }
            return count == 1
                ? "1 file is still downloading from iCloud. Try again when it is on this device."
                : "\(count) files are still downloading from iCloud. Try again when they are on this device."
        }
    }
}
