import BackgroundTasks

@MainActor
protocol ImportActivityTask: AnyObject {
    func setTaskCompleted(success: Bool)
    func report(_ step: ImportStep)
}

/// Shows one import outside the app as a continued-processing task: the system draws it, and it keeps the app
/// polling the server while it is in the background.
@MainActor
enum ImportActivity {
    @MainActor
    enum State {
        case idle
        case requested(id: String, title: String, step: ImportStep)
        case running(task: any ImportActivityTask, step: ImportStep)
        case ended(id: String, success: Bool)

        enum Event {
            case adopt(task: any ImportActivityTask, id: String)
            case update(ImportStep)
            case end(success: Bool)
            case expire(task: any ImportActivityTask)
        }

        func send(_ event: Event) -> State {
            switch event {
            case let .adopt(task, id):
                return adopted(task, id: id)
            case let .update(step):
                return updated(step)
            case let .end(success):
                return ended(success: success)
            case let .expire(task):
                return expired(task)
            }
        }

        private func adopted(_ task: any ImportActivityTask, id: String) -> State {
            switch self {
            case let .requested(current, _, step) where current == id:
                task.report(step)
                return .running(task: task, step: step)
            case let .ended(ended, success) where ended == id:
                task.setTaskCompleted(success: success)
                return .idle
            default:
                task.setTaskCompleted(success: true)
                return self
            }
        }

        private func updated(_ step: ImportStep) -> State {
            switch self {
            case let .requested(id, title, _):
                return .requested(id: id, title: title, step: step)
            case let .running(task, shown):
                guard step != shown else {
                    return self
                }
                task.report(step)
                return .running(task: task, step: step)
            case .idle, .ended:
                return self
            }
        }

        private func ended(success: Bool) -> State {
            switch self {
            case let .running(task, _):
                task.setTaskCompleted(success: success)
                return .idle
            case let .requested(id, _, _):
                return .ended(id: id, success: success)
            case .idle, .ended:
                return .idle
            }
        }

        private func expired(_ task: any ImportActivityTask) -> State {
            task.setTaskCompleted(success: true)
            guard case let .running(bound, _) = self, bound === task else {
                return self
            }
            return .idle
        }
    }

    private(set) static var state = State.idle

    static func start(title: String, step: ImportStep) {
        state = state.send(.end(success: true))
        let id = "local.fnmn.reader.import.\(UUID().uuidString)"
        guard request(id: id, title: title, step: step) else {
            return
        }
        state = .requested(id: id, title: title, step: step)
    }

    static func update(_ step: ImportStep) {
        state = state.send(.update(step))
    }

    static func end(status: String) {
        state = state.send(.end(success: status == "Ready"))
    }

    /// iOS grants continued runtime only while the task reports progress; the server job runs either way.
    private static func request(id: String, title: String, step: ImportStep) -> Bool {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { task in
            MainActor.assumeIsolated {
                adopt(task, id: id)
            }
        }
        guard registered else {
            return false
        }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: title, subtitle: step.text)
        request.strategy = .fail
        // The server job runs whether or not iOS grants the time, so a refused request only loses the background progress.
        Task { try? await BGTaskScheduler.shared.submitTaskRequest(request) }
        return true
    }

    private static func adopt(_ task: BGTask, id: String) {
        guard let task = task as? BGContinuedProcessingTask else {
            return
        }
        // The system calls this on a queue of its own, so it hops to the main actor instead of assuming it is there.
        // The server job keeps running while the app is suspended, so losing the time is not a failed import.
        task.expirationHandler = { [weak task] in
            Task { @MainActor in
                guard let task else {
                    return
                }
                state = state.send(.expire(task: task))
            }
        }
        state = state.send(.adopt(task: task, id: id))
    }
}

extension BGContinuedProcessingTask: ImportActivityTask {
    func report(_ step: ImportStep) {
        progress.totalUnitCount = 100
        progress.completedUnitCount = Int64((step.fraction ?? 0) * 100)
        updateTitle(title, subtitle: step.text)
    }
}
