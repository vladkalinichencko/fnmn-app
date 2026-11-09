import Foundation

struct WidgetItem: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var source: String?
    var progress: Double
    var piece: Int?
    var cover: String?
    var kind: String
}

struct WidgetPost: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var text: String
    var author: String
    var network: String
}

struct WidgetDigest: Codable, Equatable, Sendable {
    var id: String
    var deliveredAt: Date
    var posts: [WidgetPost]
}

struct WidgetSnapshot: Codable, Equatable, Sendable {
    var items: [WidgetItem] = []
    var spares: [WidgetItem] = []
    var digest: WidgetDigest?
    var generatedAt: Date = .now
    var sparesChosenAt: Date = .distantPast

    func spare(at date: Date) -> WidgetItem? {
        guard !spares.isEmpty else {
            return nil
        }
        let halfDays = Int(date.timeIntervalSince1970 / 43_200)
        return spares[abs(halfDays) % spares.count]
    }
}

enum WidgetStore {
    static let group = "group.local.fnmn.reader"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static var snapshotFile: URL? {
        container?.appending(path: "widget.json")
    }

    static var coversFolder: URL? {
        container?.appending(path: "widget-covers", directoryHint: .isDirectory)
    }

    static func read() -> WidgetSnapshot? {
        guard let snapshotFile, let data = try? Data(contentsOf: snapshotFile) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let snapshotFile else {
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        try? data.write(to: snapshotFile, options: .atomic)
    }

    static func cover(named name: String?) -> URL? {
        guard let name, let coversFolder else {
            return nil
        }
        return coversFolder.appending(path: name)
    }

    static func storeCover(from source: URL, as name: String) {
        guard let coversFolder else {
            return
        }
        try? FileManager.default.createDirectory(at: coversFolder, withIntermediateDirectories: true)
        let destination = coversFolder.appending(path: name)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: source, to: destination)
    }
}

extension WidgetItem {
    var deepLink: URL {
        var components = URLComponents()
        components.scheme = "fnmn"
        components.host = "item"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        if let piece {
            components.queryItems?.append(URLQueryItem(name: "piece", value: String(piece)))
        }
        return components.url ?? URL(string: "fnmn://continue")!
    }
}

