import FNMNCore
import Foundation
import Testing

/// Reads a real FNMN folder into a copy of a device's library the way the app does, and prints any archive
/// that fails. It runs only when both paths are given:
///   FNMN_PROBE_FOLDER=~/Library/Mobile\ Documents/com~apple~CloudDocs/FNMN FNMN_PROBE_STATE=<copied Application Support/FNMN> \
///   swift test --filter realFolderReads
@Test func realFolderReads() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let folderPath = env["FNMN_PROBE_FOLDER"], let statePath = env["FNMN_PROBE_STATE"] else { return }
    let folder = URL(filePath: folderPath)
    let work = FileManager.default.temporaryDirectory.appending(path: "probe-\(UUID())")
    try FileManager.default.copyItem(at: URL(filePath: statePath), to: work)
    let file = LibraryFile(url: work, cache: work.appending(path: "cache"))
    await file.useCloudFolder(folder)
    var snapshot = try await file.load().catalog
    snapshot = try await file.applyBrowserCatalog(from: folder, into: snapshot)
    let deliveries = try FileManager.default.contentsOfDirectory(at: folder.appending(path: "deliveries"), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "tar" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    for delivery in deliveries {
        do {
            snapshot = try await file.addCloudDelivery(delivery, into: snapshot)
        } catch {
            print("PROBE FAIL \(delivery.lastPathComponent): \(error)")
        }
    }
    try await file.save(snapshot)
    print("PROBE DONE articles \(snapshot.articles.count) albums \(snapshot.albums)")
}
