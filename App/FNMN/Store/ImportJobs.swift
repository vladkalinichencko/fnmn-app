import FNMNCore
import Foundation
import Observation

/// One link or file on its way into the library. It shows as a tile in Unsorted until it is stored.
struct ImportJob: Identifiable, Equatable {
    enum Input: Equatable {
        case link(URL)
        case file(URL)
        /// The FNMN folder in iCloud Drive, chosen as the library's home and read.
        case libraryFolder(URL)
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
        case let .file(url), let .libraryFolder(url): url.lastPathComponent
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
            case let .file(url): try await importFile(url, jobID: job.id)
            case let .libraryFolder(folder): try await library.linkLibraryFolder(folder) { self.send(.progressed(job.id, $0)) }
            case let .videoFile(itemID, url): try await downloadVideo(url, itemID: itemID, jobID: job.id)
            }
            send(.finished(job.id))
        } catch {
            send(.failed(job.id, error.localizedDescription))
        }
    }

    private func prepare(_ url: URL, jobID: UUID) async throws {
        guard CaptureRoute.source(for: url) != nil else { throw CaptureError.unrecognizedDocument }
        if try await storedFromMac(jobID: jobID, start: { try await self.mac.port.startJob(url: url, connection: $0) }) == nil {
            try await library.storeMade(.link(url))
        }
    }

    /// A prepared pick is stored as it is; any other file goes to the Mac, and its original to `originals/`.
    private func importFile(_ url: URL, jobID: UUID) async throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard !library.isPrepared(url) else {
            try await library.importFile(at: url) { self.send(.progressed(jobID, $0)) }
            return
        }
        try await CloudFolder.download(url)
        send(.progressed(jobID, .sending))
        let made = try await storedFromMac(jobID: jobID) { try await self.mac.port.startFileJob(file: url, connection: $0) }
        send(.progressed(jobID, .saving))
        let materialID = if let made { made } else { try await keep(url) }
        try await library.storeOriginal(url, of: materialID)
    }

    private func keep(_ file: URL) async throws -> String {
        let package = try ImportPackage.file(file)
        try await library.storeMade(package)
        return package.material.id
    }

    /// Runs a job on the Mac and stores the delivery it made, even a link or file it could not read.
    /// Nil when the Mac is not set up, cannot be reached or failed, and the phone keeps the link or file itself;
    /// sending it again once the Mac answers replaces that material.
    private func storedFromMac(jobID: UUID, start: (MacConnection) async throws -> MacJob) async throws -> String? {
        guard let connection = try? mac.configured() else { return nil }
        let job: MacJob
        let archive: URL
        do {
            job = try await mac.port.finished(try await start(connection), connection: connection) { send(.progressed(jobID, $0)) }
            guard job.phase == .done else { return nil }
            send(.progressed(jobID, .saving))
            archive = try await mac.port.delivery(of: job.id, connection: connection)
        } catch where !Task.isCancelled {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: archive) }
        let materialID = try await library.store(archive: archive)
        await confirmStored(job.id, connection: connection)
        return materialID
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
        let video = try await mac.port.videoFile(of: job.id, connection: connection)
        defer { try? FileManager.default.removeItem(at: video) }
        try await library.storeOriginal(video, of: itemID)
        await confirmStored(job.id, connection: connection)
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
        case .libraryFolder: .downloadingFromCloud
        }
    }
}

extension ImportStep {
    static let sending = ImportStep(text: "Sending to the Mac", fraction: nil)
    static let saving = ImportStep(text: "Saving", fraction: nil)
    static let downloadingFromCloud = ImportStep(text: "Downloading from iCloud", fraction: nil)

    static func importing(_ index: Int, of count: Int) -> ImportStep {
        ImportStep(text: "Importing \(index + 1) of \(count)", fraction: Double(index) / Double(max(count, 1)))
    }
}
