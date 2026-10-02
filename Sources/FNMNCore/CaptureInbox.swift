import Foundation

/// What the Share extension leaves for the app: a folder in the app group's container holding one entry per
/// shared link or file. The extension cannot run an import or open the app, so the app takes the entries the
/// next time it is active and imports them the way it imports a link or file added inside it.
public struct CaptureInbox: Sendable {
    public static let appGroup = "group.local.fnmn.reader"

    public enum Entry: Equatable, Sendable {
        case link(URL)
        /// A file already moved out of the inbox, into the temporary directory.
        case file(URL)
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The inbox in the app group's container; nil where the group is not available to the process.
    public init?(appGroup: String = Self.appGroup) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        self.init(directory: container.appending(path: "Inbox"))
    }

    public func drop(link: URL) throws {
        let entry = try makeEntry()
        try Data(link.absoluteString.utf8).write(to: entry.appending(path: Self.linkName))
    }

    public func drop(file: URL) throws {
        let entry = try makeEntry()
        try FileManager.default.copyItem(at: file, to: entry.appending(path: file.lastPathComponent))
    }

    /// Every entry, oldest first, removed from the inbox; a file moves to a temporary folder first so it outlives its entry.
    public func take() -> [Entry] {
        let manager = FileManager.default
        let names = ((try? manager.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        return names.compactMap { name in
            let entry = directory.appending(path: name)
            defer { try? manager.removeItem(at: entry) }
            let contents = (try? manager.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []
            if let text = try? String(contentsOf: entry.appending(path: Self.linkName), encoding: .utf8), let link = URL(string: text) {
                return .link(link)
            }
            guard let file = contents.first else { return nil }
            let kept = manager.temporaryDirectory.appending(path: UUID().uuidString)
            let destination = kept.appending(path: file.lastPathComponent)
            guard (try? manager.createDirectory(at: kept, withIntermediateDirectories: true)) != nil,
                  (try? manager.moveItem(at: file, to: destination)) != nil else { return nil }
            return .file(destination)
        }
    }

    private static let linkName = "link.txt"

    /// Named by the time so entries come back in the order they were shared.
    private func makeEntry() throws -> URL {
        let entry = directory.appending(path: "\(String(format: "%020.6f", Date.now.timeIntervalSince1970))-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
        return entry
    }
}
