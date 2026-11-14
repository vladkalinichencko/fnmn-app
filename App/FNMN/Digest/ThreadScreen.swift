import FNMNCore
import SwiftUI
import Textual

struct ThreadScreen: View {
    let postID: String
    @Environment(DigestModel.self) private var digests

    var body: some View {
        ScrollView {
            if let digest = digests.digest(of: postID), let post = digest.package.posts.first(where: { $0.id == postID }) {
                let own = post.comments.filter { isAuthor($0, of: post) }
                let others = post.comments.filter { !isAuthor($0, of: post) }
                VStack(alignment: .leading, spacing: Tokens.gap) {
                    if let context = post.context, let parent = context.post, context.kind == .reply {
                        parentCard(parent, kind: context.kind)
                        PostCard(post: post, digest: digest, showsContext: false)
                    } else {
                        PostCard(post: post, digest: digest, showsContext: false)
                        if let context = post.context, let parent = context.post {
                            parentCard(parent, kind: context.kind)
                        }
                    }
                    ForEach(Array(own.enumerated()), id: \.offset) { _, comment in
                        commentCard(comment)
                    }
                    if !others.isEmpty {
                        Text("Replies")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(others.enumerated()), id: \.offset) { _, comment in
                            commentCard(comment)
                        }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, Tokens.gap)
                .padding(.bottom, Tokens.sectionGap)
            } else if let contextPost = digests.contextPost(postID) {
                contextPostCard(contextPost)
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
        digests.post(postID)?.author.name ?? digests.contextPost(postID)?.author.name ?? "Thread"
    }

    private func isAuthor(_ comment: DigestPackage.Post.Comment, of post: DigestPackage.Post) -> Bool {
        if let handle = comment.handle {
            return handle.caseInsensitiveCompare(post.author.handle) == .orderedSame
        }
        return comment.author == post.author.name
    }

    private func parentCard(_ post: DigestPackage.Post.ContextPost, kind: DigestPackage.Post.Context.Kind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PostContextLabel(kind: kind, text: "\(kind.action) \(post.author.name)")
                Spacer(minLength: 8)
                PostOpenButton(url: post.permalink, label: "Open the post that is quoted")
            }
            if let text = post.text {
                PostText(text: text)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contextPostCard(_ post: DigestPackage.Post.ContextPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(post.author.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(post.network.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PostOpenButton(url: post.permalink, label: "Open the post in \(post.network.name)")
                Spacer(minLength: 8)
            }
            if let text = post.text {
                PostText(text: text)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentCard(_ comment: DigestPackage.Post.Comment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(comment.author)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let link = comment.permalink {
                    PostOpenButton(url: link, label: "Open the reply")
                }
                Spacer(minLength: 8)
            }
            PostText(text: comment.text)
        }
        .padding(.vertical, 8)
    }
}
