import FNMNCore
import Foundation

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
    static func run(_ target: some DeliveryTarget, in folder: URL?) async -> (failures: [String], pending: Int) {
        let archives: [URL]
        do {
            archives = try await CloudFolder.archives(in: folder, subfolder: target.subfolder)
        } catch {
            return (["the \(target.subfolder) folder could not be read: \(error.localizedDescription)"], 0)
        }
        let changed: [URL]
        do {
            changed = try await target.changed(archives)
        } catch {
            return (["the \(target.subfolder) index could not be read: \(error.localizedDescription)"], 0)
        }
        var failures: [String] = []
        var pending = 0
        for (index, archive) in changed.enumerated() {
            do {
                try await CloudFolder.download(archive)
                try await target.add(archive, index: index, total: changed.count)
            } catch CloudFolderError.notDownloaded(_, _) {
                pending += 1
            } catch {
                failures.append("\(archive.lastPathComponent): \(error.localizedDescription)")
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
