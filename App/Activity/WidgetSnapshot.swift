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
        spares(from: date, count: 1).first
    }

    func spares(from date: Date, count: Int) -> [WidgetItem] {
        guard !spares.isEmpty, count > 0 else {
            return []
        }
        let halfDays = Int(date.timeIntervalSince1970 / 43_200)
        let start = abs(halfDays) % spares.count
        return (0..<count).map { spares[(start + $0) % spares.count] }
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

    static func pruneCovers(keeping names: Set<String>) {
        guard let coversFolder, let files = try? FileManager.default.contentsOfDirectory(at: coversFolder, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
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


extension WidgetPost {
    var deepLink: URL {
        var components = URLComponents()
        components.scheme = "fnmn"
        components.host = "digest"
        components.queryItems = [URLQueryItem(name: "post", value: id)]
        return components.url ?? URL(string: "fnmn://digest")!
    }
}

extension WidgetSnapshot {
    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            items: [
                WidgetItem(id: "article:one", title: "A Talk on Representation Learning", source: "Distill", progress: 0.42, piece: 12, cover: nil, kind: "article"),
                WidgetItem(id: "article:two", title: "Why Momentum Really Works", source: "Distill", progress: 0.18, piece: 4, cover: nil, kind: "article"),
                WidgetItem(id: "article:three", title: "Attention Is All You Need", source: "arXiv", progress: 0.66, piece: 30, cover: nil, kind: "article"),
            ],
            spares: [],
            digest: WidgetDigest(
                id: "digest",
                deliveredAt: .now,
                posts: [
                    WidgetPost(id: "p1", text: "A model that reads its own output is not checking anything.", author: "Someone", network: "X"),
                    WidgetPost(id: "p2", text: "The batch size changes which negatives exist, not only how many.", author: "Somebody", network: "Telegram"),
                    WidgetPost(id: "p3", text: "An ablation that removes one term tells you where the gain lives.", author: "Else", network: "X"),
                    WidgetPost(id: "p4", text: "Every ranking is a policy, and a policy can be measured.", author: "Another", network: "Telegram"),
                ]
            )
        )
    }
}
