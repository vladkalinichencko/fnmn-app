import ActivityKit

final class ImportActivityHandle: @unchecked Sendable {
    private let activity: Activity<ImportActivityAttributes>

    init(_ activity: Activity<ImportActivityAttributes>) {
        self.activity = activity
    }

    func update(status: String, fraction: Double) async {
        let state = ImportActivityAttributes.ContentState(status: status, fraction: fraction)
        await activity.update(.init(state: state, staleDate: nil))
    }

    func end(status: String) async {
        let state = ImportActivityAttributes.ContentState(status: status, fraction: 1)
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
    }
}

enum ImportActivity {
    nonisolated(unsafe) private static var current: ImportActivityHandle?

    static func start(title: String, status: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = ImportActivityAttributes.ContentState(status: status, fraction: 0.3)
        guard let activity = try? Activity.request(
            attributes: ImportActivityAttributes(title: title),
            content: .init(state: state, staleDate: nil),
            pushType: nil
        ) else { return }
        current = ImportActivityHandle(activity)
    }

    static func update(status: String, fraction: Double) async {
        await current?.update(status: status, fraction: fraction)
    }

    static func end(status: String) async {
        let handle = current
        current = nil
        await handle?.end(status: status)
    }
}
