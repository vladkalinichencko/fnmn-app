import ActivityKit
import BackgroundTasks

/// Shows one import outside the app: a Live Activity, and a continued-processing task
/// that keeps the app polling the Mac while it is in the background.
@MainActor
enum ImportActivity {
    private static var activity: LiveActivity?
    private static var background: BGContinuedProcessingTask?
    private static var backgroundID: String?
    private static var step: ImportStep?

    static func start(title: String, step: ImportStep) {
        self.step = step
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = (try? Activity.request(
                attributes: ImportActivityAttributes(title: title),
                content: .init(state: state(step), staleDate: nil),
                pushType: nil
            )).map(LiveActivity.init)
        }
        requestBackgroundTime(title: title, step: step)
    }

    static func update(_ step: ImportStep) async {
        self.step = step
        report(step, to: background)
        await activity?.update(state(step))
    }

    static func end(status: String) async {
        let finished = activity
        activity = nil
        backgroundID = nil
        step = nil
        background?.setTaskCompleted(success: status == "Ready")
        background = nil
        let final = ImportActivityAttributes.ContentState(status: status, fraction: 1)
        await finished?.end(final)
    }

    private static func state(_ step: ImportStep) -> ImportActivityAttributes.ContentState {
        ImportActivityAttributes.ContentState(status: step.text, fraction: step.fraction)
    }

    /// iOS grants continued runtime only while the task reports progress; the Mac job runs either way.
    private static func requestBackgroundTime(title: String, step: ImportStep) {
        let identifier = "local.fnmn.reader.import.\(UUID().uuidString)"
        backgroundID = identifier
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { adopt(task, identifier: identifier) }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: step.text)
        request.strategy = .fail
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func adopt(_ task: BGTask, identifier: String) {
        guard let task = task as? BGContinuedProcessingTask else { return }
        guard identifier == backgroundID, let step else {
            task.setTaskCompleted(success: true)
            return
        }
        task.expirationHandler = { MainActor.assumeIsolated { background = nil } }
        task.progress.totalUnitCount = 100
        background = task
        report(step, to: task)
    }

    private static func report(_ step: ImportStep, to task: BGContinuedProcessingTask?) {
        guard let task else { return }
        task.updateTitle(task.title, subtitle: step.text)
        task.progress.completedUnitCount = Int64((step.fraction ?? 0) * 100)
    }
}

/// ActivityKit's Activity is not Sendable; it is only touched through these two calls.
private final class LiveActivity: @unchecked Sendable {
    private let activity: Activity<ImportActivityAttributes>

    init(_ activity: Activity<ImportActivityAttributes>) {
        self.activity = activity
    }

    func update(_ state: ImportActivityAttributes.ContentState) async {
        await activity.update(.init(state: state, staleDate: nil))
    }

    func end(_ state: ImportActivityAttributes.ContentState) async {
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
    }
}
