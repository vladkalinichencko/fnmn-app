@testable import FNMNCore
import Foundation
import Testing

/// Writes a delivery the way the server's `write_delivery` does: USTAR, `package.json` first, then the files.
func writeDelivery(_ package: ImportPackage, files: [(String, Data)] = [], to url: URL) throws {
    try writeTar(package: try JSONEncoder().encode(package), files: files, to: url)
}

/// The same uncompressed USTAR archive for any package JSON, so a digest reads through the same reader.
func writeTar(package: Data, files: [(String, Data)] = [], to url: URL) throws {
    var archive = Data()
    func add(_ name: String, _ data: Data) {
        var header = [UInt8](repeating: 0, count: 512)
        func put(_ text: String, at offset: Int) {
            for (index, byte) in text.utf8.enumerated() { header[offset + index] = byte }
        }
        put(name, at: 0)
        put("0000644", at: 100)
        put("0000000", at: 108)
        put("0000000", at: 116)
        put(String(format: "%011o", data.count), at: 124)
        put("00000000000", at: 136)
        put("        ", at: 148)
        put("0", at: 156)
        put("ustar", at: 257)
        put("00", at: 263)
        put(String(format: "%06o", header.reduce(0) { $0 + Int($1) }), at: 148)
        archive.append(contentsOf: header)
        archive.append(data)
        archive.append(Data(count: (512 - data.count % 512) % 512))
    }
    add("package.json", package)
    for (name, data) in files { add(name, data) }
    archive.append(Data(count: 1024))
    try archive.write(to: url)
}

private let package = ImportPackage(
    material: Material(id: "article:a", kind: .article, title: "A", sourceURL: URL(string: "https://example.com/a")!),
    sections: [],
    blocks: [],
    body: "Text ![p](assets/p.png)"
)

@Test func aDeliveryUnpacksItsPackageAndEveryFileInOnePass() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let large = Data((0..<200_000).map { UInt8($0 % 251) })
    let files = [("assets/p.png", Data("png".utf8)), ("empty.txt", Data()), ("block.bin", Data(count: 512)), ("assets/large.bin", large)]
    let archive = folder.appending(path: "a.tar")
    try writeDelivery(package, files: files, to: archive)
    let unpacked = try DeliveryArchive(url: archive).unpack { unpackedPackage, path in
        #expect(unpackedPackage == package)
        return folder.appending(path: "out").appending(path: path)
    }
    #expect(unpacked == package)
    for (name, data) in files {
        #expect(try Data(contentsOf: folder.appending(path: "out").appending(path: name)) == data)
    }
}

@Test func aDeliveryWithoutItsPackageFirstIsRefused() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let archive = folder.appending(path: "a.tar")
    try Data(count: 1024).write(to: archive)
    #expect(throws: DeliveryArchiveError.missingPackage) {
        try DeliveryArchive(url: archive).unpack { (_: ImportPackage, path: String) in folder.appending(path: path) }
    }
}
