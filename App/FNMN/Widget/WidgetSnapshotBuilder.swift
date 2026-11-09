import CryptoKit
import FNMNCore
import Foundation
import WidgetKit

@MainActor
enum WidgetSnapshotBuilder {
    static func refresh(library: LibraryModel, digests: DigestModel) async {
        var snapshot = WidgetStore.read() ?? WidgetSnapshot()
        snapshot.items = library.queries.continueItems(library.progress).prefix(8).map { item(for: $0, library: library) }
        let stale = Date.now.timeIntervalSince(snapshot.sparesChosenAt) > 43_200
        if snapshot.spares.isEmpty || stale {
            snapshot.spares = library.queries.items.shuffled().prefix(12).map { item(for: $0, library: library) }
            snapshot.sparesChosenAt = .now
        }
        snapshot.digest = digests.current.map { digest in
            WidgetDigest(
                id: digest.id,
                deliveredAt: digest.package.window.to,
                posts: digest.package.posts.compactMap { post in
                    guard let text = post.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                        return nil
                    }
                    return WidgetPost(id: post.id, text: text, author: post.author.name, network: post.network.name)
                }.prefix(6).map { $0 }
            )
        }
        snapshot.generatedAt = .now
        WidgetStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func item(for item: LibraryItem, library: LibraryModel) -> WidgetItem {
        let kind = switch item.kind {
        case .article: "article"
        case .video: "video"
        case .book: "book"
        case .link: "link"
        }
        return WidgetItem(
            id: item.id,
            title: item.title,
            source: item.source?.name,
            progress: library.progress.readings[item.id]?.progress ?? 0,
            piece: library.position(of: item.id)?.pieceIndex,
            cover: cover(for: item, library: library),
            kind: kind
        )
    }

    private static func cover(for item: LibraryItem, library: LibraryModel) -> String? {
        guard case let .stored(materialID) = item.cover else {
            return nil
        }
        let source = LibraryFile.coverFile(root: library.storageURL, materialID: materialID)
        guard FileManager.default.fileExists(atPath: source.path) else {
            return nil
        }
        let name = SHA256.hash(data: Data(item.id.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg"
        WidgetStore.storeCover(from: source, as: name)
        return name
    }
}
