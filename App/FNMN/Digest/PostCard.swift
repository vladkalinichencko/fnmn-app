import FNMNCore
import SwiftUI
import Textual

struct PostCard: View {
    let post: DigestPackage.Post
    let digest: Digest
    let read: Bool
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
                PostText(text: text)
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
            openThread()
        }
        .contextMenu {
            menu
        }
        .accessibilityAction(named: "Open the thread") {
            openThread()
        }
    }

    private func openThread() {
        guard opensThread else {
            return
        }
        navigation.open(.thread(post.id))
    }

    private var header: some View {
        PostAuthorLine(name: post.author.name, handle: post.author.handle) {
            Text("\(post.network.name) · \(post.postedAt.formatted(.relative(presentation: .numeric)))")
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
            PostOpenButton(url: post.permalink, label: "Open the post in \(post.network.name)", font: .callout)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder private var menu: some View {
        Button("Save to Library", systemImage: "books.vertical") {
            let link = digests.save(post, digest: digest)
            imports.send(.submit(.link(link), id: UUID()))
        }
        Button("Open in \(post.network.name)", systemImage: "arrow.up.right.square") {
            openURL(post.permalink)
        }
        Button("Hide", systemImage: "eye.slash") {
            digests.record(.hidden, post: post, digest: digest)
        }
    }

    private var mediaRadius: CGFloat {
        Tokens.concentric(Tokens.plateRadius, inset: Tokens.tilePadding)
    }

    static func icon(_ kind: DigestPackage.Post.Context.Kind) -> String {
        switch kind {
        case .reply: "arrowshape.turn.up.left"
        case .repost: "arrow.2.squarepath"
        case .quote: "quote.opening"
        }
    }

    static func contextLabel(_ context: DigestPackage.Post.Context) -> String {
        let handle = context.post.map { "@\($0.author.handle)" } ?? "a post that is gone"
        return "\(context.kind.action) \(handle)"
    }

    static func length(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let rest = total % 60
        return String(format: "%d:%02d", minutes, rest)
    }
}
