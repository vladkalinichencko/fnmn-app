import Foundation

public struct ReadingModeEvent: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case rsvp, spot
    }

    public let itemID: String
    public let mode: Mode
    public let wordsPerMinute: Int
    public let pauses: String
    public let words: Int
    public let backs: Int
    public let startedAt: Date
    public let endedAt: Date

    public init(itemID: String, mode: Mode, wordsPerMinute: Int, pauses: String, words: Int, backs: Int, startedAt: Date, endedAt: Date) {
        self.itemID = itemID
        self.mode = mode
        self.wordsPerMinute = wordsPerMinute
        self.pauses = pauses
        self.words = words
        self.backs = backs
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}
