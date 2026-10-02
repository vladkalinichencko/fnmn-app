@testable import FNMNCore
import Foundation
import Testing

@Test func theInboxGivesBackLinksAndFilesInTheOrderTheyWereShared() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let inbox = CaptureInbox(directory: root.appending(path: "Inbox"))
    let pdf = root.appending(path: "paper.pdf")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("pdf".utf8).write(to: pdf)

    try inbox.drop(link: URL(string: "https://example.com/a")!)
    try inbox.drop(file: pdf)
    try inbox.drop(link: URL(string: "https://example.com/b")!)

    let entries = inbox.take()
    #expect(entries.count == 3)
    #expect(entries[0] == .link(URL(string: "https://example.com/a")!))
    guard case let .file(file) = entries[1] else {
        Issue.record("second entry is not a file")
        return
    }
    #expect(file.lastPathComponent == "paper.pdf")
    #expect(try Data(contentsOf: file) == Data("pdf".utf8))
    #expect(entries[2] == .link(URL(string: "https://example.com/b")!))
    #expect(inbox.take().isEmpty)
}
