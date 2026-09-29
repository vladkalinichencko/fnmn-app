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
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @Environment(\.openURL) private var openURL

    private var progress: Double? {
        library.progress.readings[item.id]?.progress
    }

    var body: some View {
        Button(action: open) {
            if let cover = item.cover {
                coverTile(cover)
            } else {
                TileCard(progress: progress) {
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
                .padding(.bottom, (progress ?? 0) > 0 ? ProgressLine.clearance - (Tokens.tilePadding - 2) : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay { ProgressLine(progress: progress, cornerRadius: Tokens.captionRadius) }
                .glassEffect(.regular, in: .rect(cornerRadius: Tokens.captionRadius, style: .continuous))
                .padding(Tokens.captionInset)
            }
            .clipShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
            .contentShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
    }

    private var title: some View {
        Text(item.title)
            .font(.title3.weight(.black))
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
            let isRead = library.progress.readings[item.id]?.isRead ?? false
            Button(isRead ? "Mark as Unread" : "Mark as Read", systemImage: isRead ? "circle" : "checkmark.circle") {
                library.apply(.setRead(!isRead, itemID: item.id))
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
                    .font(.title3.weight(.black))
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
    let progress: Double?
    let content: Content

    init(progress: Double? = nil, @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.content = content()
    }

    var body: some View {
        content
            .padding(Tokens.tilePadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .aspectRatio(Tokens.tileAspect, contentMode: .fit)
            .overlay { ProgressLine(progress: progress, cornerRadius: Tokens.tileRadius) }
            .plate(cornerRadius: Tokens.tileRadius)
            .contentShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
    }
}

/// How far a material is read: a straight line inside the glass along its bottom edge. It spans the edge's
/// flat part, so its rounded ends sit where the corners start to curve.
struct ProgressLine: View {
    let progress: Double?
    let cornerRadius: CGFloat

    /// How far the line stays from the bottom edge, and the room text above it keeps.
    static let inset: CGFloat = 9
    static let thickness: CGFloat = 5
    static var clearance: CGFloat { inset + thickness + 6 }

    var body: some View {
        if let progress, progress > 0 {
            GeometryReader { geometry in
                Capsule()
                    .fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(geometry.size.width * min(progress, 1), Self.thickness))
                    }
            }
            .frame(height: Self.thickness)
            .padding(.horizontal, cornerRadius)
            .padding(.bottom, Self.inset)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        }
    }
}

struct CoverImage: View {
    let cover: Cover
    var cornerRadius: CGFloat = Tokens.concentric(Tokens.tileRadius, inset: Tokens.tilePadding)
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.1))
            .overlay {
                switch cover {
                case let .articleFile(materialID, path):
                    if let url = library.articleFile(materialID, path: path) {
                        FileImage(url: url, contentMode: .fill)
                    }
                case let .remote(url):
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
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
