import ActivityKit

struct ImportActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var status: String
        var fraction: Double?
    }

    var title: String
}
