import Foundation

/// A folder picked from iCloud Drive may hold only placeholders on this device: the file
/// `deliveries/abc.tar` is then `.abc.tar.icloud` until it is downloaded. Reading the folder
/// before that sees no such file, so its material would show as a bare link.
enum CloudFolder {
    /// Asks iCloud for a file, or every file under a folder, and returns when all of them are on the device.
    /// A folder holds thousands of files, so the walk runs off the main thread, and the check
    /// waits longer each time nothing new has arrived: from half a second up to five.
    @concurrent
    static func download(_ item: URL, timeout: Duration = .seconds(600)) async throws {
        var pending = missing(in: item)
        for file in pending {
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        }
        let deadline = ContinuousClock.now + timeout
        var pause = Duration.milliseconds(500)
        while !pending.isEmpty {
            guard ContinuousClock.now < deadline else { throw CloudFolderError.notDownloaded(pending.count) }
            try await Task.sleep(for: pause)
            let still = pending.filter { !isLocal($0) }
            pause = still.count == pending.count ? min(pause * 2, .seconds(5)) : .milliseconds(500)
            pending = still
        }
    }

    /// Whether a file, or every file under a folder, is already on the device.
    @concurrent
    static func isOnDevice(_ item: URL) async -> Bool {
        missing(in: item).isEmpty
    }

    /// Whether the file is in the folder, on the device or still only in iCloud.
    static func contains(_ file: URL) -> Bool {
        FileManager.default.fileExists(atPath: file.path) || FileManager.default.fileExists(atPath: placeholder(of: file).path)
    }

    /// The folder's files, or those with the extension, by the names they have once downloaded, in name order.
    @concurrent
    static func files(in folder: URL, withExtension pathExtension: String? = nil) async throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .map(downloadedName)
            .filter { pathExtension == nil ? !$0.lastPathComponent.hasPrefix(".") : $0.pathExtension == pathExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Files under the item that are still only in iCloud, by the names they will have once downloaded.
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

    /// A URL keeps the values it read until the run loop turns, and a check off the main thread has no run loop,
    /// so each check reads them afresh; otherwise a file that has since downloaded would stay missing.
    private static func isLocal(_ url: URL) -> Bool {
        var url = url
        url.removeAllCachedResourceValues()
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard values?.isUbiquitousItem == true else { return FileManager.default.fileExists(atPath: url.path) }
        return values?.ubiquitousItemDownloadingStatus == .current
    }
}

enum CloudFolderError: LocalizedError {
    case notDownloaded(Int)

    var errorDescription: String? {
        switch self {
        case let .notDownloaded(count): "\(count) files are still downloading from iCloud. Try again when they are on this device."
        }
    }
}
