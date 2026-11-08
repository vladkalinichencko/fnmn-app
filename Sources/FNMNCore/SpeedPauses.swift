import Foundation

public enum SpeedPauseKind: String, Codable, CaseIterable, Sendable {
    case comma, clause, sentence, paragraph, numbers, longWords

    public var name: String {
        switch self {
        case .comma: "Comma"
        case .clause: "Colon or Dash"
        case .sentence: "Full Stop"
        case .paragraph: "Paragraph"
        case .numbers: "Numbers"
        case .longWords: "Long Words"
        }
    }
}

public enum SpeedPauseLevel: String, Codable, CaseIterable, Sendable {
    case off, slight, regular

    public var name: String {
        switch self {
        case .off: "Off"
        case .slight: "Slight"
        case .regular: "Regular"
        }
    }

    public var share: Double {
        switch self {
        case .off: 0
        case .slight: 0.5
        case .regular: 1
        }
    }
}

public struct SpeedPauseProfile: Codable, Equatable, Sendable {
    private var levels: [SpeedPauseKind: SpeedPauseLevel]

    public init(_ level: SpeedPauseLevel = .regular) {
        levels = Dictionary(uniqueKeysWithValues: SpeedPauseKind.allCases.map { ($0, level) })
    }

    public init(legacy level: String?) {
        self.init(SpeedPauseLevel(rawValue: level ?? "") ?? .regular)
    }

    public init(json: String?) {
        let levels = json?.data(using: .utf8).flatMap { try? JSONDecoder().decode([SpeedPauseKind: SpeedPauseLevel].self, from: $0) }
        self.init(levels ?? Dictionary(uniqueKeysWithValues: SpeedPauseKind.allCases.map { ($0, .regular) }))
    }

    private init(_ levels: [SpeedPauseKind: SpeedPauseLevel]) {
        self.levels = levels
    }

    public subscript(kind: SpeedPauseKind) -> SpeedPauseLevel {
        get { levels[kind] ?? .regular }
        set { levels[kind] = newValue }
    }

    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(levels)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public mutating func set(_ level: SpeedPauseLevel, for kind: SpeedPauseKind) {
        levels[kind] = level
    }

    public func share(_ kind: SpeedPauseKind) -> Double {
        self[kind].share
    }
}
