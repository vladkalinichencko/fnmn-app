import Foundation

public struct DigestSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var hours: [Int]
    public var threshold: Double
    public var limit: Int
    public var networks: [String: Network]
    public var sources: [String: Source]

    public struct Network: Codable, Equatable, Sendable {
        public var recommendations: Bool
        public var topics: [String]

        public init(recommendations: Bool = false, topics: [String] = []) {
            self.recommendations = recommendations
            self.topics = topics
        }

        private enum CodingKeys: String, CodingKey {
            case recommendations, topics
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            recommendations = try container.decodeIfPresent(Bool.self, forKey: .recommendations) ?? false
            topics = try container.decodeIfPresent([String].self, forKey: .topics) ?? []
        }
    }

    public struct Source: Codable, Equatable, Sendable {
        public var topics: [String]

        public init(topics: [String] = []) {
            self.topics = topics
        }

        private enum CodingKeys: String, CodingKey {
            case topics
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            topics = try container.decodeIfPresent([String].self, forKey: .topics) ?? []
        }
    }

    public static let fileName = "digest-settings.json"

    public init(
        enabled: Bool = true,
        hours: [Int] = [8, 20],
        threshold: Double = 0.5,
        limit: Int = 100,
        networks: [String: Network] = [:],
        sources: [String: Source] = [:]
    ) {
        self.enabled = enabled
        self.hours = hours
        self.threshold = threshold
        self.limit = limit
        self.networks = networks
        self.sources = sources
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, hours, threshold, limit, networks, sources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        hours = try container.decodeIfPresent([Int].self, forKey: .hours) ?? [8, 20]
        threshold = try container.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.5
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 100
        networks = try container.decodeIfPresent([String: Network].self, forKey: .networks) ?? [:]
        sources = try container.decodeIfPresent([String: Source].self, forKey: .sources) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(hours, forKey: .hours)
        try container.encode(threshold, forKey: .threshold)
        try container.encode(limit, forKey: .limit)
        try container.encode(networks, forKey: .networks)
        try container.encode(sources, forKey: .sources)
    }

    public static func load(from folder: URL) -> DigestSettings {
        let url = folder.appending(path: fileName)
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(DigestSettings.self, from: data)
        else {
            return DigestSettings()
        }
        return settings
    }

    public func save(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: folder.appending(path: Self.fileName), options: .atomic)
    }
}
