import FNMNCore
import SwiftUI
import Textual

/// One post of the magazine: the author above the post's own text, its pictures under it, and a small button
/// that opens the post itself in its network. A tap opens the thread; a long press saves the post to the
/// library, opens it, or hides it.
struct PostCard: View {
    let post: DigestPackage.Post
    let digest: Digest
    let read: Bool
    /// The thread screen shows the post it was opened for, so that card does not open itself again.
    var opensThread = true
    @Environment(WindowNavigation.self) private var navigation
    @Environment(DigestModel.self) private var digests
    @Environment(ImportJobs.self) private var imports
    @Environment(\.openURL) private var openURL

    var body: some View {
        let media = digests.media(for: post)
        VStack(alignment: .leading, spacing: 10) {
            header
            if let text = post.text {
                StructuredText(text, parser: MarkedMarkdown(baseURL: nil, marks: [], width: nil))
                    .opacity(read ? Tokens.readOpacity : 1)
            }
            if let video = post.video, video.poster != nil {
                poster(video)
            }
            if (post.mediaErrors ?? 0) > 0, media.isEmpty {
                mediaPlaceholder
            }
            pictures(media)
            if let context = post.context {
                contextLine(context)
            }
            footer
        }
        .padding(Tokens.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plate(cornerRadius: Tokens.plateRadius)
        .contentShape(RoundedRectangle(cornerRadius: Tokens.plateRadius))
        .onTapGesture {
            guard opensThread else {
                return
            }
            navigation.open(.thread(post.id))
        }
        .contextMenu {
            menu
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(post.author.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("@\(post.author.handle)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(Self.network(post.network)) · \(post.postedAt.formatted(.relative(presentation: .numeric)))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private func pictures(_ media: [DigestPackage.Post.Media]) -> some View {
        if media.count == 1, let only = media.first {
            picture(only, square: false)
        } else if !media.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                ForEach(media, id: \.path) { item in
                    picture(item, square: true)
                }
            }
        }
    }

    /// A picture the source would not serve keeps the post on screen and offers the Mac another try.
    private var mediaPlaceholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
            Text("Picture unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if digests.refreshing.contains(post.id) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Retry") {
                    Task { await digests.refresh(post, digest: digest) }
                }
                .font(.caption)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func picture(_ item: DigestPackage.Post.Media, square: Bool) -> some View {
        let ratio = square ? 1 : CGFloat(item.width) / CGFloat(max(item.height, 1))
        return FileImage(url: digest.url(of: item.path), contentMode: .fill)
            .aspectRatio(ratio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: mediaRadius, style: .continuous))
    }

    /// A video the digest does not stream: its own frame, the length, and a tap that opens the post.
    private func poster(_ video: DigestPackage.Post.Video) -> some View {
        ZStack {
            if let poster = video.poster {
                FileImage(url: digest.url(of: poster.path), contentMode: .fill)
                Image(systemName: "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(.black.opacity(0.35), in: Circle())
            }
            if let duration = video.duration {
                Text(Self.length(duration))
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .aspectRatio(CGFloat(video.poster?.width ?? 16) / CGFloat(max(video.poster?.height ?? 9, 1)), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: mediaRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: mediaRadius, style: .continuous))
        .onTapGesture {
            openURL(post.permalink)
        }
    }

    private func contextLine(_ context: DigestPackage.Post.Context) -> some View {
        HStack(spacing: 6) {
            Image(systemName: Self.icon(context.kind))
                .font(.caption)
            Text(Self.contextLabel(context))
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let stats = post.stats {
                if let likes = stats.likes {
                    Label("\(likes.formatted(.number.notation(.compactName)))", systemImage: "heart")
                }
                if let replies = stats.replies {
                    Label("\(replies.formatted(.number.notation(.compactName)))", systemImage: "bubble.left")
                }
                if let reposts = stats.reposts {
                    Label("\(reposts.formatted(.number.notation(.compactName)))", systemImage: "arrow.2.squarepath")
                }
            }
            Spacer()
            Button {
                openURL(post.permalink)
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the post in \(Self.network(post.network))")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder private var menu: some View {
        Button("Save to Library", systemImage: "books.vertical") {
            let link = digests.save(post, digest: digest)
            imports.send(.submit(.link(link), id: UUID()))
        }
        Button("Open in \(Self.network(post.network))", systemImage: "arrow.up.right.square") {
            openURL(post.permalink)
        }
        Button("Hide", systemImage: "eye.slash") {
            digests.record(.hidden, post: post, digest: digest)
        }
    }

    /// A picture sits inside the plate's padding, so its corner shares the plate's center.
    private var mediaRadius: CGFloat {
        Tokens.concentric(Tokens.plateRadius, inset: Tokens.tilePadding)
    }

    static func network(_ name: DigestPackage.Network) -> String {
        name.name
    }

    static func icon(_ kind: DigestPackage.Post.Context.Kind) -> String {
        switch kind {
        case .reply: "arrowshape.turn.up.left"
        case .quote: "quote.opening"
        }
    }

    static func contextLabel(_ context: DigestPackage.Post.Context) -> String {
        let handle = context.post.map { "@\($0.author.handle)" } ?? "a post that is gone"
        return switch context.kind {
        case .reply: "Replying to \(handle)"
        case .quote: "Quoting \(handle)"
        }
    }

    static func length(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let rest = total % 60
        return String(format: "%d:%02d", minutes, rest)
    }
}
