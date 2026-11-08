import XCTest
@testable import FNMN

/// The background task is one machine: it is completed once, with the status the import actually ended with,
/// even when the system adopts the request after the import is over.
@MainActor
final class ImportActivityTests: XCTestCase {
    private final class FakeTask: ImportActivityTask {
        var completed: [Bool] = []
        var steps: [ImportStep] = []

        func setTaskCompleted(success: Bool) {
            completed.append(success)
        }

        func report(_ step: ImportStep) {
            steps.append(step)
        }
    }

    private let step = ImportStep.sending
    private let later = ImportStep.saving

    private func requested() -> ImportActivity.State {
        .requested(id: "one", title: "Import", step: step)
    }

    private func assertIdle(_ state: ImportActivity.State, file: StaticString = #filePath, line: UInt = #line) {
        guard case .idle = state else {
            XCTFail("the activity is idle", file: file, line: line)
            return
        }
    }

    private func assertEnded(
        _ state: ImportActivity.State,
        id: String,
        success: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .ended(ended, endedSuccess) = state, ended == id, endedSuccess == success else {
            XCTFail("the activity ended for \(id) with \(success)", file: file, line: line)
            return
        }
    }

    func testAdoptingTheRequestBindsTheTaskAndReportsTheStep() {
        let task = FakeTask()
        let state = requested().send(.adopt(task: task, id: "one"))
        guard case let .running(bound, shown) = state else {
            XCTFail("the task is bound")
            return
        }
        XCTAssertTrue(bound === task)
        XCTAssertEqual(shown, step)
        XCTAssertEqual(task.steps, [step])
    }

    func testATaskForAnotherRequestIsCompletedAndChangesNothing() {
        let task = FakeTask()
        let state = requested().send(.adopt(task: task, id: "other"))
        guard case let .requested(id, _, _) = state else {
            XCTFail("the request still waits")
            return
        }
        XCTAssertEqual(id, "one")
        XCTAssertEqual(task.completed, [true])
    }

    func testAnImportThatEndedBeforeAdoptionCompletesWithItsOwnStatus() {
        let failed = requested().send(.end(success: false))
        assertEnded(failed, id: "one", success: false)

        let task = FakeTask()
        assertIdle(failed.send(.adopt(task: task, id: "one")))
        XCTAssertEqual(task.completed, [false])
    }

    func testEndingARunningTaskCompletesItOnce() {
        let task = FakeTask()
        let running = requested().send(.adopt(task: task, id: "one"))
        assertIdle(running.send(.end(success: true)))
        XCTAssertEqual(task.completed, [true])
    }

    func testAStageAlreadyReportedIsNotReportedTwice() {
        let task = FakeTask()
        let running = requested().send(.adopt(task: task, id: "one"))
        _ = running.send(.update(step))
        XCTAssertEqual(task.steps, [step])

        _ = running.send(.update(later))
        XCTAssertEqual(task.steps, [step, later])
    }

    func testAStageBeforeAdoptionIsTheOneTheTaskStartsWith() {
        let task = FakeTask()
        let updated = requested().send(.update(later))
        guard case let .requested(_, _, shown) = updated else {
            XCTFail("still requested")
            return
        }
        XCTAssertEqual(shown, later)
        _ = updated.send(.adopt(task: task, id: "one"))
        XCTAssertEqual(task.steps, [later])
    }

    func testExpiringTheBoundTaskEndsTheActivityAndLeavesAnotherTaskAlone() {
        let task = FakeTask()
        let running = requested().send(.adopt(task: task, id: "one"))
        let other = FakeTask()

        guard case .running = running.send(.expire(task: other)) else {
            XCTFail("the bound task stays")
            return
        }
        XCTAssertEqual(other.completed, [true])
        assertIdle(running.send(.expire(task: task)))
        XCTAssertEqual(task.completed, [true])
    }

    func testIdleIgnoresEveryLaterEvent() {
        let task = FakeTask()
        assertIdle(ImportActivity.State.idle.send(.update(step)))
        assertIdle(ImportActivity.State.idle.send(.end(success: true)))
        neverAdopted(task)
    }

    private func neverAdopted(_ task: FakeTask) {
        assertIdle(ImportActivity.State.idle.send(.adopt(task: task, id: "one")))
        XCTAssertEqual(task.completed, [true])
        XCTAssertTrue(task.steps.isEmpty)
    }
}
