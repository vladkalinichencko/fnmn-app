import FNMNCore
import Foundation
import Testing

@Test func realFolderReads() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let folderPath = env["FNMN_PROBE_FOLDER"], let statePath = env["FNMN_PROBE_STATE"] else { return }
    let folder = URL(filePath: folderPath)
    let work = FileManager.default.temporaryDirectory.appending(path: "probe-\(UUID())")
    try FileManager.default.copyItem(at: URL(filePath: statePath), to: work)
    let file = LibraryFile(url: work, cache: work.appending(path: "cache"))
    await file.useCloudFolder(folder)
    var snapshot = try await file.load().catalog
    snapshot = try await file.applyBrowserCatalogIfChanged(from: folder, into: snapshot) ?? snapshot
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
