import CryptoKit
import Foundation

public struct ArticleEntry: Codable, Equatable, Sendable {
    public let material: Material
    public let excerpt: String?
    public let cover: Cover?
    public let searchText: String
    public let textDigest: String
    public let delivery: String?
    public let deliveredAt: Date?

    public init(_ package: ImportPackage, delivery: String? = nil, deliveredAt: Date? = nil) {
        material = package.material
        self.deliveredAt = deliveredAt
        excerpt = switch package.material.kind {
        case .video: package.material.byline
        case .link: package.material.sourceURL?.host()
        case .article, .book: ArticleBody.excerpt(package.body)
        }
        self.delivery = delivery
        cover = switch (package.cover, delivery) {
        case (.articleFile?, _?): .stored(materialID: package.material.id)
        case let (cover, _): cover
        }
        let markdown = ArticleBody.readingMarkdown(body: package.body, blocks: package.blocks)
        let fields = [package.material.title, package.material.sourceURL?.absoluteString ?? "", package.material.byline ?? ""]
            + package.sections.map(\.title) + ArticleBody.headings(in: markdown).map(\.title)
        searchText = TextFold.folded(fields.joined(separator: "\n"))
        textDigest = Self.digest(package)
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

extension ArticleEntry {
    public var originalStem: String? {
        delivery.map { ($0 as NSString).deletingPathExtension }
    }

    public func originalName(pathExtension: String) -> String? {
        originalStem.map { pathExtension.isEmpty ? $0 : "\($0).\(pathExtension)" }
    }
}

extension ImportPackage {
    var cover: Cover? {
        if material.kind == .video {
            return material.sourceURL.flatMap(YouTube.videoID(in:))
                .flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/hqdefault.jpg") }
                .map(Cover.remote)
        }
        guard let body, let path = ArticleBody.firstImagePath(body) else { return nil }
        return .articleFile(materialID: material.id, path: path)
    }
}
