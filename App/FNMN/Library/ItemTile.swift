import FNMNCore
import SwiftUI

/// A grid of material tiles; the same grid serves Library, albums, sources, search and the archive.
struct ItemGrid: View {
    let items: [LibraryItem]
    var album: String?

    var body: some View {
        LazyVGrid(columns: Tokens.grid, spacing: Tokens.gap) {
            ForEach(items) { item in
                ItemTile(item: item, album: album)
            }
        }
    }
}

struct ItemTile: View {
    let item: LibraryItem
    var album: String?
    @Environment(WindowNavigation.self) private var navigation
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: open) {
            if let cover = item.cover {
                coverTile(cover)
            } else {
                TileCard(progress: item.progress) {
                    VStack(alignment: .leading, spacing: 8) {
                        header
                        title
                        if let excerpt = item.excerpt {
                            Text(excerpt)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .draggable(item.id)
        .contextMenu { ItemActions(item: item, album: album) }
    }

    /// A tile with a picture has no frame: the picture fills it and the title sits on glass that bends it.
    private func coverTile(_ cover: Cover) -> some View {
        Color.clear
            .aspectRatio(Tokens.tileAspect, contentMode: .fit)
            .overlay { CoverImage(cover: cover, cornerRadius: 0) }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    header
                    title.lineLimit(3)
                }
                .padding(Tokens.tilePadding - 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ProgressFill(progress: item.progress))
                .clipShape(.rect(cornerRadius: Tokens.tileRadius - 8, style: .continuous))
                .glassEffect(.regular, in: .rect(cornerRadius: Tokens.tileRadius - 8, style: .continuous))
                .padding(8)
            }
            .clipShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
            .contentShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
    }

    private var title: some View {
        Text(item.title)
            .font(.title3.bold())
            .lineLimit(4)
            .multilineTextAlignment(.leading)
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

/// The rounded glass card every tile without a picture is drawn on.
struct TileCard<Content: View>: View {
    var progress: Double?
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(Tokens.tilePadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .aspectRatio(Tokens.tileAspect, contentMode: .fit)
            .background(ProgressFill(progress: progress))
            .clipShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
            .plate(cornerRadius: Tokens.tileRadius)
            .contentShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
    }
}

/// How far a material is read, as the accent color rising from the bottom and fading out upward.
struct ProgressFill: View {
    let progress: Double?

    var body: some View {
        GeometryReader { geometry in
            if let progress, progress > 0 {
                LinearGradient(colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0)], startPoint: .bottom, endPoint: .top)
                    .frame(height: geometry.size.height * min(progress, 1))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}

struct CoverImage: View {
    let cover: Cover
    var cornerRadius: CGFloat = Tokens.tileRadius - Tokens.tilePadding
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
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }

    private var url: URL? {
        switch cover {
        case let .articleFile(materialID, path): library.articleFile(materialID, path: path)
        case let .remote(url): url
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
