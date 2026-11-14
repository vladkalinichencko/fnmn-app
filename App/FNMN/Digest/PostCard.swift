import FNMNCore
import SwiftUI
import Textual

extension DigestPackage.Post {
    var hasThread: Bool {
        context != nil || !comments.isEmpty
    }
}

struct PostCard: View {
    let post: DigestPackage.Post
    let digest: Digest
    var opensThread = false
    var showsContext = true
    @Environment(WindowNavigation.self) private var navigation
    @Environment(DigestModel.self) private var digests
    @Environment(ImportJobs.self) private var imports
    @Environment(\.openURL) private var openURL

    var body: some View {
        if opensThread {
            card.zoomSource(of: post.id)
        } else {
            card
        }
    }

    private var card: some View {
        cardContent
            .background {
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .onTapGesture {
                        openThread()
                    }
                    .contextMenu {
                        menu
                    } preview: {
                        cardPeek
                    }
            }
            .accessibilityAction(named: "Open the thread") {
                openThread()
            }
    }

    private var cardContent: some View {
        let media = digests.media(for: post)
        return HStack(alignment: .top, spacing: 12) {
            if opensThread {
                Rectangle()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 10) {
                header
                if let text = post.text {
                    PostText(text: text)
                }
                if let video = post.video, video.poster != nil {
                    poster(video)
                }
                if (post.mediaErrors ?? 0) > 0, media.isEmpty {
                    mediaPlaceholder
                }
                pictures(media)
                if showsContext, let context = post.context {
                    contextBlock(context)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardPeek: some View {
        let media = digests.media(for: post)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(post.author.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(post.network.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            if let text = post.text {
                Text(Self.peekText(text))
                    .font(.callout)
                    .lineLimit(10)
            }
            if let thumb = media.first ?? post.video?.poster {
                FileImage(url: digest.url(of: thumb.path), contentMode: .fill)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: mediaRadius, style: .continuous))
            }
        }
        .padding(Tokens.tilePadding)
        .frame(width: 300, alignment: .topLeading)
        .plate(cornerRadius: Tokens.plateRadius)
    }

    private static func peekText(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }

    private func openThread() {
        guard opensThread else {
            return
        }
        navigation.open(.thread(post.id))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(post.author.name)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            PostOpenButton(url: post.permalink, label: "Open the post in \(post.network.name)", font: .callout)
            Spacer(minLength: 8)
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
                    .progressViewStyle(GraySpinner())
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
            .opensMedia(digest.url(of: item.path))
    }

    @ViewBuilder private func poster(_ video: DigestPackage.Post.Video) -> some View {
        let poster = ZStack {
            if let poster = video.poster {
                FileImage(url: digest.url(of: poster.path), contentMode: .fill)
                Image(systemName: "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(.black.opacity(0.35), in: Circle())
            }
        }
        .aspectRatio(CGFloat(video.poster?.width ?? 16) / CGFloat(max(video.poster?.height ?? 9, 1)), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: mediaRadius, style: .continuous))
        if let file = video.file {
            poster.opensMedia(digest.url(of: file.path))
        } else if let media = video.poster {
            poster.opensMedia(digest.url(of: media.path))
        } else {
            poster
        }
    }

    private func contextBlock(_ context: DigestPackage.Post.Context) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(.secondary.opacity(0.4))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                PostContextLabel(kind: context.kind, text: Self.contextLabel(context))
                if let text = context.post?.text {
                    Text(Self.peekText(text))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.leading, 8)
        .modifier(ContextTap(context: context))
    }

    private struct ContextTap: ViewModifier {
        let context: DigestPackage.Post.Context
        @Environment(WindowNavigation.self) private var navigation

        func body(content: Content) -> some View {
            if context.post != nil {
                content.contentShape(.rect).onTapGesture { open() }
            } else {
                content
            }
        }

        private func open() {
            guard let quoted = context.post else {
                return
            }
            navigation.open(.thread(quoted.id))
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Save to Library", systemImage: "books.vertical") {
            imports.send(.submit(.link(post.permalink), id: UUID()))
        }
        Button("Open in \(post.network.name)", systemImage: "arrow.up.right.square") {
            openURL(post.permalink)
        }
        Button("Hide", systemImage: "eye.slash") {
            digests.hide(post)
        }
    }

    private var mediaRadius: CGFloat {
        Tokens.concentric(Tokens.plateRadius, inset: Tokens.tilePadding)
    }

    static func estimatedHeight(_ post: DigestPackage.Post, width: CGFloat) -> Double {
        var total = 120.0
        if let text = post.text, !text.isEmpty {
            total += (Double(text.count) / max(width / 8.5, 20)).rounded(.up) * 21
        }
        if post.media.count == 1, let only = post.media.first {
            total += width * Double(only.height) / Double(max(only.width, 1))
        } else if !post.media.isEmpty {
            total += Double((post.media.count + 1) / 2) * width / 2
        }
        if let poster = post.video?.poster {
            total += width * Double(poster.height) / Double(max(poster.width, 1))
        }
        if post.context != nil {
            total += 40
        }
        if (post.mediaErrors ?? 0) > 0, post.media.isEmpty {
            total += 30
        }
        return total
    }

    static func icon(_ kind: DigestPackage.Post.Context.Kind) -> String {
        switch kind {
        case .reply: "arrowshape.turn.up.left"
        case .repost: "arrow.2.squarepath"
        case .quote: "quote.opening"
        }
    }

    static func contextLabel(_ context: DigestPackage.Post.Context) -> String {
        let name = context.post.map { $0.author.name } ?? "a post that is gone"
        return "\(context.kind.action) \(name)"
    }
}
