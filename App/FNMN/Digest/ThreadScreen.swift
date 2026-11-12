import FNMNCore
import SwiftUI
import Textual

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
                    PostCard(post: post, digest: digest)
                    if !post.comments.isEmpty {
                        comments(post, digest: digest)
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, Tokens.gap)
                .padding(.bottom, Tokens.sectionGap)
            } else {
                ContentUnavailableView("The post is gone", systemImage: "text.bubble")
            }
        }
        .modifier(ReaderAppearanceModifier())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        digests.post(postID)?.author.handle ?? "Thread"
    }

    private func parentCard(_ post: DigestPackage.Post.ContextPost, kind: DigestPackage.Post.Context.Kind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PostAuthorLine(name: post.author.name, handle: post.author.handle, size: .compact) {
                Text(kind.action)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let text = post.text {
                PostText(text: text)
                    .font(.footnote)
            }
            HStack {
                Spacer()
                PostOpenButton(url: post.permalink, label: "Open the post that is quoted")
            }
            .foregroundStyle(.tertiary)
        }
        .padding(Tokens.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plate(cornerRadius: Tokens.plateRadius)
    }

    private func comments(_ post: DigestPackage.Post, digest: Digest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Replies")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(post.comments.enumerated()), id: \.offset) { _, comment in
                HStack(alignment: .top, spacing: 10) {
                    avatar(comment, digest: digest)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(comment.author)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if let handle = comment.handle {
                                Text("@\(handle)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if let link = comment.permalink {
                                PostOpenButton(url: link, label: "Open the reply", font: .caption2)
                            }
                        }
                        Text(comment.text)
                            .font(.callout)
                    }
                }
            }
        }
    }

    private func avatar(_ comment: DigestPackage.Post.Comment, digest: Digest) -> some View {
        Group {
            if let avatar = comment.avatar {
                FileImage(url: digest.url(of: avatar.path), contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(.circle)
    }
}
