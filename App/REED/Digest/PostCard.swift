import REEDCore
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
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
                    attachments
                    if (post.mediaErrors ?? 0) > 0, post.attachments.isEmpty {
                        mediaPlaceholder
                    }
                    if showsContext, let context = post.context {
                        contextBlock(context)
                    }
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cardPeek: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            if let thumb = peekThumbnail {
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

    private var peekThumbnail: DigestPackage.Post.Media? {
        for attachment in post.attachments {
            switch attachment {
            case .image(let media): return media
            case .video(let video): if let poster = video.poster { return poster }
            case .card(let card): if let image = card.image { return image }
            }
        }
        return nil
    }

    static func peekText(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var text = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        for range in text.runs.filter({ $0.link != nil }).map(\.range) {
            text[range].link = nil
        }
        return text
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

    private var attachmentRuns: [[DigestPackage.Post.Attachment]] {
        var runs: [[DigestPackage.Post.Attachment]] = []
        for attachment in post.attachments {
            if attachment.image != nil, runs.last?.first?.image != nil {
                runs[runs.count - 1].append(attachment)
            } else {
                runs.append([attachment])
            }
        }
        return runs
    }

    @ViewBuilder private var attachments: some View {
        ForEach(Array(attachmentRuns.enumerated()), id: \.offset) { _, run in
            if run.count == 1, let only = run.first {
                attachment(only, square: false)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    ForEach(Array(run.enumerated()), id: \.offset) { _, item in
                        attachment(item, square: true)
                    }
                }
            }
        }
    }

    @ViewBuilder private func attachment(_ attachment: DigestPackage.Post.Attachment, square: Bool) -> some View {
        switch attachment {
        case .image(let media):
            picture(media, square: square)
        case .video(let video):
            poster(video)
        case .card(let card):
            cardPreview(card)
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

    @ViewBuilder private func cardPreview(_ card: DigestPackage.Post.Card) -> some View {
        let tile = VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption2)
                Text(card.domain ?? card.url?.host() ?? "Link")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let url = card.url {
                    PostOpenButton(url: url, label: "Open the link")
                }
            }
            .foregroundStyle(.secondary)
            if let title = card.title {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(3)
            }
            if let description = card.description {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let image = card.image {
                FileImage(url: digest.url(of: image.path), contentMode: .fill)
                    .aspectRatio(CGFloat(image.width) / CGFloat(max(image.height, 1)), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: mediaRadius, style: .continuous))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: mediaRadius, style: .continuous))
        if let url = card.url {
            tile
                .contentShape(.rect)
                .onTapGesture { openURL(url) }
                .accessibilityLabel("Open the link")
        } else {
            tile
        }
    }

    @ViewBuilder private func contextBlock(_ context: DigestPackage.Post.Context) -> some View {
        if let post = context.post {
            ContextPostBlock(kind: context.kind, post: post, lines: 3)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                PostContextLabel(kind: context.kind, text: Self.contextLabel(context))
            }
            .padding(.leading, 8)
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Save to Library", systemImage: "books.vertical") {
            imports.send(.submit(.link(post.permalink), id: UUID()))
        }
        Button("Open in \(post.network.name)", systemImage: "arrow.up.right.square") {
            openURL(post.permalink)
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
        var index = 0
        while index < post.attachments.count {
            switch post.attachments[index] {
            case .image:
                var end = index
                while end < post.attachments.count, post.attachments[end].image != nil {
                    end += 1
                }
                let count = end - index
                if count == 1, let media = post.attachments[index].image {
                    total += width * Double(media.height) / Double(max(media.width, 1))
                } else {
                    total += Double((count + 1) / 2) * width / 2
                }
                index = end
            case .video(let video):
                if let poster = video.poster {
                    total += width * Double(poster.height) / Double(max(poster.width, 1))
                }
                index += 1
            case .card(let card):
                total += 120
                if let image = card.image {
                    total += width * Double(image.height) / Double(max(image.width, 1)) * 0.5
                }
                index += 1
            }
        }
        if post.context != nil {
            total += 40
        }
        if (post.mediaErrors ?? 0) > 0, post.attachments.isEmpty {
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

struct ContextPostBlock: View {
    let kind: DigestPackage.Post.Context.Kind
    let post: DigestPackage.Post.ContextPost
    var lines: Int? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(.secondary.opacity(0.4))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    PostContextLabel(kind: kind, text: "\(kind.action) \(post.author.name)")
                    Spacer(minLength: 8)
                    PostOpenButton(url: post.permalink, label: "Open the post in \(post.network.name)")
                }
                if let text = post.text {
                    textView(text)
                }
            }
        }
        .padding(.leading, 8)
        .modifier(ContextTap(postID: post.id))
    }

    @ViewBuilder private func textView(_ text: String) -> some View {
        if let lines {
            Text(PostCard.peekText(text))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(lines)
        } else {
            PostText(text: text)
        }
    }
}

private struct ContextTap: ViewModifier {
    let postID: String
    @Environment(WindowNavigation.self) private var navigation

    func body(content: Content) -> some View {
        content.contentShape(.rect).onTapGesture { open() }
    }

    private func open() {
        navigation.open(.thread(postID))
    }
}
