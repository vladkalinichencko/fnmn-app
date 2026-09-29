import Foundation

/// A folder picked from iCloud Drive may hold only placeholders on this device: the file
/// `deliveries/abc.json` is then `.abc.json.icloud` until it is downloaded. Reading the folder
/// before that sees no such file, so its material would show as a bare link.
enum CloudFolder {
    /// Asks iCloud for every file under the folder and returns when all of them are on the device.
    static func download(_ folder: URL, timeout: Duration = .seconds(600)) async throws {
        var pending = missing(in: folder)
        for file in pending {
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        }
        let deadline = ContinuousClock.now + timeout
        while !pending.isEmpty {
            guard ContinuousClock.now < deadline else { throw CloudFolderError.notDownloaded(pending.count) }
            try await Task.sleep(for: .milliseconds(500))
            pending = pending.filter { !isLocal($0) }
        }
    }

    /// Files under the folder that are still only in iCloud, by the names they will have once downloaded.
    private static func missing(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
        return walk.compactMap { $0 as? URL }.compactMap { url in
            let name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                return url.deletingLastPathComponent().appending(path: String(name.dropFirst().dropLast(".icloud".count)))
            }
            return isLocal(url) ? nil : url
        }
    }

    private static func isLocal(_ url: URL) -> Bool {
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
