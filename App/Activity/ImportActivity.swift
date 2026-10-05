import BackgroundTasks

/// Shows one import outside the app as a continued-processing task: the system draws it, and it keeps the app
/// polling the server while it is in the background.
@MainActor
enum ImportActivity {
    private static var background: BGContinuedProcessingTask?
    private static var backgroundID: String?
    private static var step: ImportStep?

    static func start(title: String, step: ImportStep) {
        self.step = step
        requestBackgroundTime(title: title, step: step)
    }

    static func update(_ step: ImportStep) async {
        guard step != self.step else { return }
        self.step = step
        report(step, to: background)
    }

    static func end(status: String) async {
        backgroundID = nil
        step = nil
        background?.setTaskCompleted(success: status == "Ready")
        background = nil
    }

    /// iOS grants continued runtime only while the task reports progress; the server job runs either way.
    private static func requestBackgroundTime(title: String, step: ImportStep) {
        let identifier = "local.fnmn.reader.import.\(UUID().uuidString)"
        backgroundID = identifier
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { adopt(task, identifier: identifier) }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: step.text)
        request.strategy = .fail
        // The server job runs whether or not iOS grants the time, so a refused request only loses the background progress.
        Task { try? await BGTaskScheduler.shared.submitTaskRequest(request) }
    }

    private static func adopt(_ task: BGTask, identifier: String) {
        guard let task = task as? BGContinuedProcessingTask else { return }
        guard identifier == backgroundID, let step else {
            task.setTaskCompleted(success: true)
            return
        }
        // The system calls this on a queue of its own, so it hops to the main actor instead of assuming it is there.
        // The server job keeps running while the app is suspended.
        task.expirationHandler = {
            Task { @MainActor in
                background?.setTaskCompleted(success: false)
                background = nil
            }
        }
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
