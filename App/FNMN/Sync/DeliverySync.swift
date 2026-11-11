import FNMNCore
import Foundation
import os

enum SyncLog {
    static let library = Logger(subsystem: "local.fnmn.reader", category: "LibrarySync")
}

@MainActor
protocol DeliveryTarget {
    var subfolder: String {
        get
    }
    func changed(_ archives: [URL]) async throws -> [URL]
    func add(_ archive: URL, index: Int, total: Int) async throws
    func finish(_ archives: [URL]) async throws
}

@MainActor
enum DeliverySync {
    static func run(
        _ target: some DeliveryTarget,
        in folder: URL?,
        download: @escaping (URL) async throws -> Void = { try await CloudFolder.download($0) }
    ) async -> (failures: [String], pending: [URL]) {
        let archives: [URL]
        do {
            archives = try await CloudFolder.archives(in: folder, subfolder: target.subfolder)
        } catch {
            return (["the \(target.subfolder) folder could not be read: \(error.localizedDescription)"], [])
        }
        let changed: [URL]
        do {
            changed = try await target.changed(archives)
        } catch {
            return (["the \(target.subfolder) index could not be read: \(error.localizedDescription)"], [])
        }
        SyncLog.library.log("Changed \(target.subfolder, privacy: .public): \(changed.map(\.lastPathComponent), privacy: .public)")
        var failures: [String] = []
        var pending: [URL] = []
        for (index, archive) in changed.enumerated() {
            do {
                try await download(archive)
                try await target.add(archive, index: index, total: changed.count)
                SyncLog.library.log("Imported \(archive.lastPathComponent, privacy: .public)")
            } catch CloudFolderError.notDownloaded(_, _) {
                pending.append(archive)
                SyncLog.library.log("Pending \(archive.lastPathComponent, privacy: .public): waiting for iCloud")
            } catch {
                failures.append("\(archive.lastPathComponent): \(error.localizedDescription)")
                SyncLog.library.error("Failed \(archive.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        do {
            try await target.finish(archives)
        } catch {
            failures.append("the \(target.subfolder) folder could not be finished: \(error.localizedDescription)")
        }
        return (failures, pending)
    }
}

enum DeliverySyncError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}
