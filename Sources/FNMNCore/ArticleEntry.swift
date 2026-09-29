import CryptoKit
import Foundation

/// A prepared article or video as the catalog lists it. Its text stays on disk and is read when the reader
/// opens it; what the screens show of it is worked out once, when it enters the library.
public struct ArticleEntry: Codable, Equatable, Sendable {
    public let material: Material
    public let excerpt: String?
    public let cover: Cover?
    /// Title, address, byline, section titles and headings, one per line and folded for search.
    public let searchText: String
    /// Changes exactly when the text does, so a new text is noticed without the old one in memory.
    public let textDigest: String

    public init(_ package: ImportPackage) {
        material = package.material
        excerpt = package.material.kind == .video ? package.material.byline : ArticleBody.excerpt(package.body)
        cover = package.cover
        let markdown = ArticleBody.readingMarkdown(body: package.body, blocks: package.blocks)
        let fields = [package.material.title, package.material.sourceURL.absoluteString, package.material.byline ?? ""]
            + package.sections.map(\.title) + ArticleBody.headings(in: markdown).map(\.title)
        searchText = Self.folded(fields.joined(separator: "\n"))
        textDigest = Self.digest(package)
    }

    /// A query folded the same way; searching is then a plain substring test.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func digest(_ package: ImportPackage) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var hash = SHA256()
        hash.update(data: Data((package.body ?? "").utf8))
        hash.update(data: (try? encoder.encode(package.blocks)) ?? Data())
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ImportPackage {
    var cover: Cover? {
        if material.kind == .video {
            return YouTube.videoID(in: material.sourceURL)
                .flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/hqdefault.jpg") }
                .map(Cover.remote)
        }
        guard let body, let path = ArticleBody.firstImagePath(body) else { return nil }
        return .articleFile(materialID: material.id, path: path)
    }
}
