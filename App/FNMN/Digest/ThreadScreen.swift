import FNMNCore
import SwiftUI
import Textual

/// One post with the chain it belongs to: the post it quotes or answers above it, the post itself, and the
/// replies it drew under it. Opening the thread is what tells the Mac the post was read.
struct ThreadScreen: View {
    let postID: String
    @Environment(DigestModel.self) private var digests

    var body: some View {
        ScrollView {
            if let digest = digests.digest(of: postID), let post = digest.package.posts.first(where: { $0.id == postID }) {
                VStack(alignment: .leading, spacing: Tokens.gap) {
                    if let context = post.context, let parent = context.post {
                        parentCard(parent, kind: context.kind)
                    }
                    PostCard(post: post, digest: digest, read: false, opensThread: false)
                    if !post.comments.isEmpty {
                        comments(post)
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, Tokens.gap)
                .padding(.bottom, Tokens.sectionGap)
                .task {
                    digests.record(.opened, post: post, digest: digest)
                }
            } else {
                ContentUnavailableView("The post is gone", systemImage: "text.bubble")
            }
        }
        .background(Tokens.canvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        digests.post(postID)?.author.handle ?? "Thread"
    }

    /// The post being answered or quoted, set smaller than the one the thread was opened for.
    private func parentCard(_ post: DigestPackage.Post.ContextPost, kind: DigestPackage.Post.Context.Kind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(post.author.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text("@\(post.author.handle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(kind == .reply ? "Replying to" : kind == .repost ? "Reposting" : "Quoting")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let text = post.text {
                StructuredText(text, parser: MarkedMarkdown(baseURL: nil, marks: [], width: nil))
                    .font(.footnote)
            }
            HStack {
                Spacer()
                Button {
                    openURL(post.permalink)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open the post that is quoted")
            }
            .foregroundStyle(.tertiary)
        }
        .padding(Tokens.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plate(cornerRadius: Tokens.plateRadius)
    }

    private func comments(_ post: DigestPackage.Post) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Replies")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(post.comments.enumerated()), id: \.offset) { _, comment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(comment.author)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if let link = comment.permalink {
                            Button {
                                openURL(link)
                            } label: {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    Text(comment.text)
                        .font(.callout)
                }
                .padding(Tokens.tilePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .plate(cornerRadius: Tokens.plateRadius)
            }
        }
    }

    @Environment(\.openURL) private var openURL
}
