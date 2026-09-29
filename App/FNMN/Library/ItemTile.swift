import FNMNCore
import SwiftUI

/// A grid of material tiles; the same grid serves Library, albums, sources, search and the archive.
struct ItemGrid: View {
    let items: [LibraryItem]
    var album: String?

    var body: some View {
        GlassEffectContainer {
            LazyVGrid(columns: Tokens.grid, spacing: Tokens.gap) {
                ForEach(items) { item in
                    ItemTile(item: item, album: album)
                }
            }
        }
    }
}

struct ItemTile: View {
    let item: LibraryItem
    var album: String?
    @Environment(WindowNavigation.self) private var navigation
    @Environment(\.openURL) private var openURL
    @Environment(\.tileNamespace) private var tiles

    var body: some View {
        Button(action: open) {
            TileCard {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    Text(item.title)
                        .font(.title3.bold())
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                    content
                    Spacer(minLength: 0)
                    if let progress = item.progress, item.kind != .link {
                        ProgressView(value: progress)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .modifier(ZoomSource(id: item.id, namespace: tiles))
        .draggable(item.id)
        .contextMenu { ItemActions(item: item, album: album) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if let date = item.addedAt {
                Text(date.formatted(date: .numeric, time: .omitted))
            } else if let source = item.source {
                Text(source.name).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let symbol = item.kind.badge {
                Image(systemName: symbol)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var content: some View {
        if let cover = item.cover {
            CoverImage(cover: cover)
        } else if let excerpt = item.excerpt {
            Text(excerpt)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
        }
    }

    private func open() {
        if item.kind == .link, let url = item.originalURL {
            openURL(url)
        } else {
            navigation.open(.item(item.id))
        }
    }
}

/// Everything a material offers from its tile, the same on every screen.
struct ItemActions: View {
    let item: LibraryItem
    var album: String?
    @Environment(LibraryModel.self) private var library
    @Environment(LibraryDialogs.self) private var dialogs

    var body: some View {
        Button("Add to Album…", systemImage: "rectangle.stack.badge.plus") {
            dialogs.send(.pickAlbum(itemID: item.id))
        }
        if let album {
            Button("Remove from Album", systemImage: "rectangle.stack.badge.minus") {
                Task { await library.apply(.removeFromAlbum(album, itemID: item.id)) }
            }
        }
        if item.kind != .link {
            Button(item.isRead ? "Mark as Unread" : "Mark as Read", systemImage: item.isRead ? "circle" : "checkmark.circle") {
                Task { await library.apply(.setRead(!item.isRead, itemID: item.id)) }
            }
        }
        if let url = item.originalURL {
            ShareLink(item: url)
            Link(destination: url) { Label("Open Original", systemImage: "arrow.up.right") }
        }
        let archived = library.snapshot.isArchived(item.id)
        Button(archived ? "Unarchive" : "Archive", systemImage: "archivebox") {
            Task { await library.apply(.setArchived(!archived, itemID: item.id)) }
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            dialogs.send(.confirmDelete(itemID: item.id))
        }
    }
}

/// A material still on its way from the Mac or from a file.
struct PreparingTile: View {
    let job: ImportJob
    @Environment(ImportJobs.self) private var imports

    var body: some View {
        TileCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(job.title)
                    .font(.title3.bold())
                    .lineLimit(3)
                switch job.phase {
                case let .preparing(step):
                    Text(step.text).font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let fraction = step.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                    }
                case let .failed(message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                    Spacer(minLength: 0)
                }
            }
        }
        .contextMenu {
            if case .failed = job.phase {
                Button("Try Again", systemImage: "arrow.clockwise") { imports.send(.retry(job.id)) }
            }
            Button("Remove", systemImage: "xmark", role: .destructive) { imports.send(.dismiss(job.id)) }
        }
    }
}

/// The rounded card every tile is drawn on.
struct TileCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(Tokens.tilePadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .aspectRatio(Tokens.tileAspect, contentMode: .fit)
            .plate(cornerRadius: Tokens.tileRadius)
            .contentShape(.rect(cornerRadius: Tokens.tileRadius))
    }
}

struct CoverImage: View {
    let cover: Cover
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
            .overlay {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.1)
                }
            }
            .clipShape(.rect(cornerRadius: Tokens.tileRadius - Tokens.tilePadding))
    }

    private var url: URL? {
        switch cover {
        case let .articleFile(materialID, path): library.articleFile(materialID, path: path)
        case let .remote(url): url
        }
    }
}

/// Marks a tile as the origin of the zoom into its material, when it sits in a navigation stack.
private struct ZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

extension LibraryItem.Kind {
    var badge: String? {
        switch self {
        case .article: nil
        case .video: "play.fill"
        case .book: "book.closed"
        case .link: "arrow.up.right"
        }
    }
}
