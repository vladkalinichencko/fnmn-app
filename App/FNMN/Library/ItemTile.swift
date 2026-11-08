import FNMNCore
import SwiftUI

/// A grid of material tiles; the same grid serves Library, albums, sources, search and the archive.
struct ItemGrid: View {
    let items: [LibraryItem]
    var album: String?
    var query = ""

    var body: some View {
        LazyVGrid(columns: Tokens.grid, spacing: Tokens.gap) {
            ForEach(items) { item in
                ItemTile(item: item, album: album, query: query)
            }
        }
    }
}

struct ItemTile: View {
    let item: LibraryItem
    var album: String?
    var query = ""
    @Environment(LibraryModel.self) private var library
    @Environment(ImportJobs.self) private var imports
    @Environment(WindowNavigation.self) private var navigation
    @Environment(\.openURL) private var openURL

    private var progress: Double? {
        library.progress.readings[item.id]?.progress
    }

    /// The server preparing this material, or a download for it; its stage replaces the kind in the header.
    private var job: ImportJob? {
        imports.job(of: item.id)
    }

    var body: some View {
        let job = job
        Button(action: open) {
            if let cover = item.cover {
                coverTile(cover, job: job)
            } else {
                TileCard(progress: job?.fraction ?? progress, color: job == nil ? .accentColor : .secondary) {
                    VStack(alignment: .leading, spacing: 8) {
                        header(job)
                        title
                        if let excerpt = item.excerpt {
                            marked(excerpt)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(job == nil ? 6 : 3)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        if let job { JobStatus(phase: job.phase) }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .zoomSource(of: item.id)
        .draggable(item.id)
        .contextMenu { ItemActions(item: item, album: album) }
    }

    /// A tile with a picture has no frame: the picture fills it, its lower half eases into the plate color under the
    /// title, and the title sits on glass that bends it.
    private func coverTile(_ cover: Cover, job: ImportJob?) -> some View {
        let progress = job?.fraction ?? progress
        return Color.clear
            .aspectRatio(Tokens.tileAspect, contentMode: .fit)
            .overlay { CoverImage(cover: cover, cornerRadius: 0) }
            .overlay {
                LinearGradient(stops: Self.fade, startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    header(job)
                    title.lineLimit(3)
                    if let job { JobStatus(phase: job.phase) }
                }
                .padding(Tokens.tilePadding - 2)
                .padding(.bottom, (progress ?? 0) > 0 ? ProgressLine.clearance - (Tokens.tilePadding - 2) : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay { ProgressLine(progress: progress, cornerRadius: Tokens.captionRadius, color: job == nil ? .accentColor : .secondary) }
                .glassEffect(.regular, in: .rect(cornerRadius: Tokens.captionRadius, style: .continuous))
                .padding(Tokens.captionInset)
            }
            .clipShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
            .contentShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
    }

    /// From clear at the tile's middle to the plate color at its bottom along an ease-in-out curve, so the picture
    /// has no visible line where the fade starts.
    private static let fade: [Gradient.Stop] = (0 ... 12).map { step in
        let t = Double(step) / 12
        return Gradient.Stop(color: Tokens.plateTint.opacity(t * t * (3 - 2 * t)), location: t)
    }

    private var title: some View {
        marked(item.title)
            .font(.title3.weight(.black))
            .lineLimit(4)
            .multilineTextAlignment(.leading)
    }

    private func marked(_ text: String) -> Text {
        guard !query.isEmpty else {
            return Text(text)
        }
        return Text(AttributedString.highlighted(text, spans: ReadingSearch.spans(of: query, in: text)))
    }

    private func header(_ job: ImportJob?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let date = item.addedAt {
                Text(date.formatted(date: .numeric, time: .omitted))
            } else if let source = item.source {
                Text(source.name).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let symbol = job?.symbol ?? item.kind.badge {
                Image(systemName: symbol)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func open() {
        if item.kind == .link {
            switch library.original(of: item.id, page: item.originalURL) {
            case let .web(url)?: openURL(url)
            case let .file(url)?: Task { await library.preview(url) }
            case nil: break
            }
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
    @Environment(ImportJobs.self) private var imports
    @Environment(LibraryDialogs.self) private var dialogs

    var body: some View {
        if let job = imports.job(of: item.id) {
            JobActions(job: job)
            Divider()
        } else if item.kind == .link, let original = library.original(of: item.id, page: item.originalURL) {
            Button("Format Again", systemImage: "arrow.clockwise") {
                switch original {
                case let .web(url): imports.send(.submit(.link(url), id: UUID()))
                case let .file(url): imports.send(.submit(.file(url), id: UUID()))
                }
            }
            Divider()
        }
        Button("Add to Collection…", systemImage: "rectangle.stack.badge.plus") {
            dialogs.send(.pickAlbum(itemID: item.id))
        }
        if let album {
            Button("Remove from Collection", systemImage: "rectangle.stack.badge.minus") {
                Task { await library.apply(.removeFromAlbum(album, itemID: item.id)) }
            }
        }
        if item.kind != .link {
            let status = library.progress.status(of: item.id)
            Button(status.isRead ? "Mark as Unread" : "Mark as Read", systemImage: status.isRead ? "circle" : "checkmark.circle") {
                library.apply(.setRead(!status.isRead, itemID: item.id))
                Task { await library.apply(.setArchived(!status.isRead, itemID: item.id)) }
            }
            if status.isStarted {
                Button("Remove from Continue", systemImage: "arrow.counterclockwise") {
                    library.apply(.reset(itemID: item.id))
                }
            }
        }
        if let url = item.originalURL {
            ShareLink(item: url)
        }
        OpenOriginalButton(itemID: item.id, page: item.originalURL)
        let archived = library.snapshot.isArchived(item.id)
        Button(archived ? "Unarchive" : "Archive", systemImage: "archivebox") {
            Task { await library.apply(.setArchived(!archived, itemID: item.id)) }
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            dialogs.send(.confirmDelete(itemID: item.id))
        }
    }
}

/// A job with no card yet: the FNMN folder being read, or a picked file still coming down from iCloud.
struct PreparingTile: View {
    let job: ImportJob

    var body: some View {
        TileCard(progress: job.fraction, color: .secondary) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: job.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(job.title)
                    .font(.title3.weight(.black))
                    .lineLimit(3)
                Spacer(minLength: 0)
                JobStatus(phase: job.phase)
            }
        }
        .contextMenu { JobActions(job: job) }
    }
}

/// What a card's job is doing, in words; its share done runs as a grey line along the card's edge, where the
/// accent line of reading progress would be. A stage with no known share shows a spinner; a failure shows its reason.
struct JobStatus: View {
    let phase: ImportJob.Phase

    var body: some View {
        HStack(spacing: 6) {
            switch phase {
            case let .preparing(step, _):
                if step.fraction == nil {
                    ProgressView().controlSize(.mini)
                }
                Text(step.text).lineLimit(1)
            case let .failed(message, _):
                Text(message).lineLimit(3)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Try Again and Dismiss for a job that failed, Stop for one still running.
struct JobActions: View {
    let job: ImportJob
    @Environment(ImportJobs.self) private var imports

    var body: some View {
        if case .failed = job.phase {
            Button("Try Again", systemImage: "arrow.clockwise") { imports.send(.retry(job.id)) }
            Button("Dismiss", systemImage: "xmark") { imports.send(.dismiss(job.id)) }
        } else {
            Button("Stop", systemImage: "stop.circle") { imports.send(.dismiss(job.id)) }
        }
    }
}

/// The rounded glass card every tile without a picture is drawn on.
struct TileCard<Content: View>: View {
    let progress: Double?
    let color: Color
    let content: Content

    init(progress: Double? = nil, color: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.color = color
        self.content = content()
    }

    var body: some View {
        content
            .padding(Tokens.tilePadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .aspectRatio(Tokens.tileAspect, contentMode: .fit)
            .overlay { ProgressLine(progress: progress, cornerRadius: Tokens.tileRadius, color: color) }
            .plate(cornerRadius: Tokens.tileRadius)
            .contentShape(.rect(cornerRadius: Tokens.tileRadius, style: .continuous))
    }
}

/// How far a material is read, or in grey how far its job is done: a straight line inside the glass along its
/// bottom edge. It spans the edge's flat part, so its rounded ends sit where the corners start to curve.
struct ProgressLine: View {
    let progress: Double?
    let cornerRadius: CGFloat
    var color: Color = .accentColor

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
                            .fill(color)
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
                case let .articleFile(materialID, _), let .stored(materialID):
                    FileImage(url: library.coverFile(materialID), contentMode: .fill)
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

extension ImportJob {
    var symbol: String {
        switch phase {
        case let .preparing(step, _): step.symbol
        case .failed: "exclamationmark.triangle"
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
