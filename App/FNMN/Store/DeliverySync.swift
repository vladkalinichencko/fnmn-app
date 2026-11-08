import FNMNCore
import Foundation

/// What one kind of delivery does with an archive: the library changes its snapshot, the digest writes its
/// cache and index. Everything around that, listing, skipping what is known, downloading and reporting a
/// failure, is the same for both and lives in `DeliverySync`.
@MainActor
protocol DeliveryTarget {
    /// The folder under the FNMN folder: `deliveries` for articles, `digests` for the digest.
    var subfolder: String { get }
    /// The archives this target still has to read, in the folder's order.
    func changed(_ archives: [URL]) async throws -> [URL]
    func add(_ archive: URL, index: Int, total: Int) async throws
    /// Runs once after every archive: the digest saves its index and prunes the cache, the library has nothing.
    func finish(_ archives: [URL]) async throws
}

/// The one loop over a folder of delivery archives. A failure is a line in the result, not a reason to stop
/// the others; the caller decides whether the first one is fatal.
@MainActor
enum DeliverySync {
    static func run(_ target: some DeliveryTarget, in folder: URL?) async -> [String] {
        let archives: [URL]
        do {
            archives = try await CloudFolder.archives(in: folder, subfolder: target.subfolder)
        } catch {
            return ["the \(target.subfolder) folder could not be read: \(error.localizedDescription)"]
        }
        let changed: [URL]
        do {
            changed = try await target.changed(archives)
        } catch {
            return ["the \(target.subfolder) index could not be read: \(error.localizedDescription)"]
        }
        var failures: [String] = []
        for (index, archive) in changed.enumerated() {
            do {
                try await CloudFolder.download(archive)
                try await target.add(archive, index: index, total: changed.count)
            } catch {
                failures.append("\(archive.lastPathComponent): \(error.localizedDescription)")
            }
        }
        do {
            try await target.finish(archives)
        } catch {
            failures.append("the \(target.subfolder) folder could not be finished: \(error.localizedDescription)")
        }
        return failures
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
