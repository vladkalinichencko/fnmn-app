import Foundation

public struct CaptureInbox: Sendable {
    public static let appGroup = "group.local.fnmn.reader"

    public enum Entry: Equatable, Sendable {
        case link(URL)
        case file(URL)
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

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

    private func makeEntry() throws -> URL {
        let entry = directory.appending(path: "\(String(format: "%020.6f", Date.now.timeIntervalSince1970))-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
        return entry
    }
}
