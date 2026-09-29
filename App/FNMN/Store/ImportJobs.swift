import FNMNCore
import Foundation
import Observation

/// One link or file on its way into the library. It shows as a tile in Unsorted until it is stored.
struct ImportJob: Identifiable, Equatable {
    enum Input: Equatable {
        case link(URL)
        case file(URL)
        /// A YouTube video the Mac downloads so the system player can play it offline.
        case videoFile(itemID: String, url: URL)
    }

    enum Phase: Equatable {
        case preparing(ImportStep)
        case failed(String)
    }

    let id: UUID
    let input: Input
    var phase: Phase

    var title: String {
        switch input {
        case let .link(url): url.host() ?? url.absoluteString
        case let .file(url): url.lastPathComponent
        case let .videoFile(_, url): url.absoluteString
        }
    }
}

enum ImportAction {
    case submit(ImportJob.Input, id: UUID)
    case progressed(UUID, ImportStep)
    case finished(UUID)
    case failed(UUID, String)
    case retry(UUID)
    case dismiss(UUID)
}

func importReduce(_ jobs: [ImportJob], _ action: ImportAction) -> [ImportJob] {
    var jobs = jobs
    func update(_ id: UUID, _ change: (inout ImportJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }
    switch action {
    case let .submit(input, id):
        jobs.insert(ImportJob(id: id, input: input, phase: .preparing(input.firstStep)), at: 0)
    case let .progressed(id, step):
        update(id) { if case .preparing = $0.phase { $0.phase = .preparing(step) } }
    case let .finished(id):
        jobs.removeAll { $0.id == id }
    case let .failed(id, message):
        update(id) { if case .preparing = $0.phase { $0.phase = .failed(message) } }
    case let .retry(id):
        update(id) { if case .failed = $0.phase { $0.phase = .preparing($0.input.firstStep) } }
    case let .dismiss(id):
        jobs.removeAll { $0.id == id }
    }
    return jobs
}

/// Runs imports for the whole app, so closing a sheet or a window never loses one.
@MainActor @Observable
final class ImportJobs {
    private(set) var jobs: [ImportJob] = []
    private let library: LibraryModel
    private let mac: MacLink
    private var shownJobID: UUID?
    @ObservationIgnored private var running: [UUID: Task<Void, Never>] = [:]

    init(library: LibraryModel, mac: MacLink) {
        self.library = library
        self.mac = mac
    }

    func send(_ action: ImportAction) {
        let before = jobs
        let next = importReduce(jobs, action)
        guard next != before else { return }
        jobs = next
        for (id, task) in running where !jobs.contains(where: { $0.id == id && $0.isPreparing }) {
            task.cancel()
            running[id] = nil
        }
        for job in jobs where job.isPreparing && !(before.first { $0.id == job.id }?.isPreparing ?? false) {
            running[job.id] = Task { await run(job) }
        }
        showFirstPreparingJob(ending: action)
    }

    private func run(_ job: ImportJob) async {
        do {
            switch job.input {
            case let .link(url): try await prepare(url, jobID: job.id)
            case let .file(url): try await importFile(url)
            case let .videoFile(itemID, url): try await downloadVideo(url, itemID: itemID, jobID: job.id)
            }
            send(.finished(job.id))
        } catch {
            send(.failed(job.id, error.localizedDescription))
        }
    }

    private func prepare(_ url: URL, jobID: UUID) async throws {
        guard CaptureRoute.source(for: url) != nil else { throw CaptureError.unrecognizedDocument }
        let connection = try mac.configured()
        let started = try await mac.port.startJob(url: url, connection: connection)
        let job = try await mac.port.finished(started, connection: connection) { send(.progressed(jobID, $0)) }
        guard job.phase == .done else {
            throw MacServiceError.rejected(job.error ?? "The Mac could not prepare this link.")
        }
        send(.progressed(jobID, .saving))
        let archive = try await mac.port.delivery(of: job.id, connection: connection)
        defer { try? FileManager.default.removeItem(at: archive) }
        try await library.store(archive: archive)
        await confirmStored(job.id, connection: connection)
    }

    /// The material is in the library whether or not the Mac hears this; a Mac that does not keeps the
    /// job's file until the service restarts, so a lost confirmation does not fail the import.
    private func confirmStored(_ id: String, connection: MacConnection) async {
        try? await mac.port.forget(id, connection: connection)
    }

    private func downloadVideo(_ url: URL, itemID: String, jobID: UUID) async throws {
        let connection = try mac.configured()
        let started = try await mac.port.startVideoDownload(url: url, connection: connection)
        let job = try await mac.port.finished(started, connection: connection) { send(.progressed(jobID, $0)) }
        guard job.phase == .done else {
            throw MacServiceError.rejected(job.error ?? "The Mac could not download this video.")
        }
        send(.progressed(jobID, .saving))
        try await library.storeVideoFile(itemID, from: try await mac.port.videoFile(of: job.id, connection: connection))
        await confirmStored(job.id, connection: connection)
    }

    private func importFile(_ url: URL) async throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try await library.importFile(at: url)
    }

    /// The Live Activity and the background task follow the oldest job still preparing.
    private func showFirstPreparingJob(ending action: ImportAction) {
        let shown = jobs.last { $0.isPreparing }
        if shown?.id != shownJobID, shownJobID != nil {
            let failed = if case .failed = action { true } else { false }
            Task { await ImportActivity.end(status: failed ? "Failed" : "Ready") }
            shownJobID = nil
        }
        guard let shown, case let .preparing(step) = shown.phase else { return }
        if shownJobID == nil {
            shownJobID = shown.id
            ImportActivity.start(title: shown.title, step: step)
        } else {
            Task { await ImportActivity.update(step) }
        }
    }
}

extension ImportJob {
    var isPreparing: Bool {
        if case .preparing = phase { true } else { false }
    }

    /// Links and files become new materials and show as tiles; a video download belongs to its video.
    var addsMaterial: Bool {
        if case .videoFile = input { false } else { true }
    }
}

extension ImportJob.Input {
    var firstStep: ImportStep {
        switch self {
        case .link, .videoFile: .sending
        case .file: .saving
        }
    }
}

extension ImportStep {
    static let sending = ImportStep(text: "Sending to the Mac", fraction: nil)
    static let saving = ImportStep(text: "Saving", fraction: nil)
}
