import FNMNCore
import Foundation
import Observation
import os

struct ImportJob: Identifiable, Equatable {
    enum Input: Equatable {
        case link(URL)
        case file(URL)
        case libraryFolder(URL)
        case videoFile(itemID: String, url: URL)
    }

    enum Place: Equatable {
        case tile
        case card(String)
    }

    enum Phase: Equatable {
        case preparing(ImportStep, on: Place)
        case failed(String, on: Place)
    }

    let id: UUID
    let input: Input
    var phase: Phase

    var itemID: String? {
        switch phase {
        case let .preparing(_, on: .card(itemID)), let .failed(_, on: .card(itemID)):
            itemID
        case .preparing(_, on: .tile), .failed(_, on: .tile):
            nil
        }
    }

    var title: String {
        switch input {
        case let .link(url): url.host() ?? url.absoluteString
        case let .file(url): url.lastPathComponent
        case let .libraryFolder(url): "The \(url.lastPathComponent) folder"
        case let .videoFile(_, url): url.absoluteString
        }
    }

    var fraction: Double? {
        if case let .preparing(step, _) = phase {
            return step.fraction
        }
        return nil
    }

    var readsLibraryFolder: Bool {
        if case .libraryFolder = input { true } else { false }
    }
}

enum ImportAction {
    case submit(ImportJob.Input, id: UUID)
    case placed(UUID, itemID: String)
    case progressed(UUID, ImportStep)
    case finished(UUID)
    case failed(UUID, String)
    case retry(UUID)
    case dismiss(UUID)
    case deleted(itemID: String)
}

func importReduce(_ jobs: [ImportJob], _ action: ImportAction) -> [ImportJob] {
    var jobs = jobs
    func update(_ id: UUID, _ change: (inout ImportJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }
    switch action {
    case let .submit(input, id):
        jobs.insert(ImportJob(id: id, input: input, phase: .preparing(input.firstStep, on: input.place)), at: 0)
    case let .placed(id, itemID):
        update(id) { job in
            guard case let .preparing(step, _) = job.phase else {
                return
            }
            job.phase = .preparing(step, on: .card(itemID))
        }
    case let .progressed(id, step):
        update(id) { job in
            guard case let .preparing(_, place) = job.phase else {
                return
            }
            job.phase = .preparing(step, on: place)
        }
    case let .finished(id):
        jobs.removeAll { $0.id == id && $0.isPreparing }
    case let .failed(id, message):
        update(id) { job in
            guard case let .preparing(_, place) = job.phase else {
                return
            }
            job.phase = .failed(message, on: place)
        }
    case let .retry(id):
        update(id) { job in
            guard case let .failed(_, place) = job.phase else {
                return
            }
            job.phase = .preparing(job.input.firstStep, on: place)
        }
    case let .dismiss(id):
        jobs.removeAll { $0.id == id }
    case let .deleted(itemID):
        jobs.removeAll { $0.itemID == itemID }
    }
    return jobs
}

@MainActor @Observable
final class ImportJobs {
    private(set) var jobs: [ImportJob] = []
    private let library: LibraryModel
    private let server: ServerLink
    private var shownJobID: UUID?
    @ObservationIgnored private var running: [UUID: Task<Void, Never>] = [:]
    private static let log = Logger(subsystem: "local.fnmn.reader", category: "import")

    init(library: LibraryModel, server: ServerLink) {
        self.library = library
        self.server = server
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

    func job(of itemID: String) -> ImportJob? {
        jobs.first { $0.itemID == itemID }
    }

    private func run(_ job: ImportJob) async {
        do {
            switch job.input {
            case let .link(url): try await addLink(url, job: job)
            case let .file(url): try await addFile(url, job: job)
            case let .libraryFolder(folder): try await library.linkLibraryFolder(folder) { self.send(.progressed(job.id, $0)) }
            case let .videoFile(itemID, url): try await downloadVideo(url, itemID: itemID, jobID: job.id)
            }
            send(.finished(job.id))
        } catch where !Task.isCancelled {
            Self.log.error("\(job.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            send(.failed(job.id, error.localizedDescription))
        } catch {}
    }

    private func addLink(_ link: URL, job: ImportJob) async throws {
        guard CaptureRoute.source(for: link) != nil else { throw CaptureError.notAWebLink }
        let url = link.withoutFragment
        if job.itemID == nil {
            try await library.storeLink(url)
            send(.placed(job.id, itemID: library.snapshot.materialID(forPage: url) ?? ImportPackage.link(url).material.id))
        }
        try await prepareOnServer(jobID: job.id) { try await self.server.port.startJob(url: url, connection: $0) }
    }

    private func addFile(_ url: URL, job: ImportJob) async throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if job.itemID == nil {
            try await CloudFolder.download(url)
            send(.progressed(job.id, .saving))
            send(.placed(job.id, itemID: try await library.storeFile(url)))
        }
        send(.progressed(job.id, .sending))
        try await prepareOnServer(jobID: job.id) { connection in
            try await self.server.port.startFileJob(file: url, connection: connection) { self.send(.progressed(job.id, $0)) }
        }
    }

    private func prepareOnServer(jobID: UUID, start: (ServerConnection) async throws -> ServerJob) async throws {
        let connection = try server.configured()
        let job = try await server.port.finished(try await start(connection), connection: connection) { send(.progressed(jobID, $0)) }
        guard job.phase == .done, job.error == nil else {
            await forget(job.id, connection: connection)
            throw ServerError.rejected(job.error ?? "The server could not prepare this item.")
        }
        let archive = try await server.port.delivery(of: job.id, connection: connection) { self.send(.progressed(jobID, $0)) }
        defer { try? FileManager.default.removeItem(at: archive) }
        send(.progressed(jobID, .saving))
        try await library.store(archive: archive)
        await forget(job.id, connection: connection)
    }

    private func forget(_ id: String, connection: ServerConnection) async {
        try? await server.port.forget(id, connection: connection)
    }

    private func downloadVideo(_ url: URL, itemID: String, jobID: UUID) async throws {
        let connection = try server.configured()
        let started = try await server.port.startVideoDownload(url: url, connection: connection)
        let job = try await server.port.finished(started, connection: connection) { send(.progressed(jobID, $0)) }
        guard job.phase == .done else {
            throw ServerError.rejected(job.error ?? "The server could not download this video.")
        }
        let video = try await server.port.videoFile(of: job.id, connection: connection) { self.send(.progressed(jobID, $0)) }
        defer { try? FileManager.default.removeItem(at: video) }
        send(.progressed(jobID, .saving))
        try await library.storeOriginal(video, of: itemID)
        await forget(job.id, connection: connection)
    }

    private func showFirstPreparingJob(ending action: ImportAction) {
        let shown = jobs.last { $0.isPreparing }
        if shown?.id != shownJobID, shownJobID != nil {
            let failed = if case .failed = action { true } else { false }
            ImportActivity.end(status: failed ? "Failed" : "Ready")
            shownJobID = nil
        }
        guard let shown, case let .preparing(step, _) = shown.phase else {
            return
        }
        if shownJobID == nil {
            shownJobID = shown.id
            ImportActivity.start(title: shown.title, step: step)
        } else {
            ImportActivity.update(step)
        }
    }
}

extension ImportJob {
    var isPreparing: Bool {
        if case .preparing = phase { true } else { false }
    }
}

extension ImportJob.Input {
    var place: ImportJob.Place {
        if let itemID {
            return .card(itemID)
        }
        return .tile
    }

    var firstStep: ImportStep {
        switch self {
        case .link, .videoFile: .sending
        case .file: .downloadingFromCloud
        case .libraryFolder: .readingLibraryFolder
        }
    }

    var itemID: String? {
        if case let .videoFile(itemID, _) = self { itemID } else { nil }
    }
}

extension ImportStep {
    static let sending = ImportStep(text: "Sending to the server", fraction: nil, symbol: "arrow.up.circle")
    static let saving = ImportStep(text: "Saving", fraction: nil, symbol: "tray.and.arrow.down")
    static let downloadingFromCloud = ImportStep(text: "Downloading from iCloud", fraction: nil, symbol: "icloud.and.arrow.down")
    static let readingLibraryFolder = ImportStep(text: "Reading the FNMN folder", fraction: nil, symbol: "folder")

    static func reading(_ done: Int, of count: Int) -> ImportStep {
        ImportStep(text: "\(done) of \(count) read", fraction: Double(done) / Double(max(count, 1)), symbol: "folder")
    }
}
