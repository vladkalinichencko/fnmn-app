import FNMNCore
import SwiftUI

struct DigestSearchResults: View {
    let query: String
    let onOpen: (DigestPackage.Post) -> Void
    @Environment(DigestModel.self) private var digests
    @Environment(\.openURL) private var openURL

    private var groups: [(digest: Digest, posts: [DigestPackage.Post])] {
        digests.digests.compactMap { digest in
            let found = digest.package.posts(matching: query, hidden: digests.hidden)
            return found.isEmpty ? nil : (digest, found)
        }
    }

    var body: some View {
        SearchResultsList(query: query, searching: false, empty: groups.isEmpty) {
            ForEach(groups, id: \.digest.id) { group in
                Section(Self.title(of: group.digest)) {
                    ForEach(group.posts) { post in
                        row(post)
                    }
                }
            }
        }
    }

    private func row(_ post: DigestPackage.Post) -> some View {
        Button {
            onOpen(post)
        } label: {
            if let excerpt = post.excerpt(matching: query) {
                ResultRow(
                    title: post.author.name,
                    subtitle: "@\(post.author.handle)",
                    excerpt: excerpt.text,
                    spans: [excerpt.span]
                )
            } else {
                ResultRow(title: post.author.name, subtitle: "@\(post.author.handle)")
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open the post in \(post.network.name)", systemImage: "safari") {
                openURL(post.permalink)
            }
        }
    }

    private static func title(of digest: Digest) -> String {
        let end = digest.package.window.to
        let period = Calendar.current.component(.hour, from: end) < 16 ? "Morning" : "Evening"
        return "\(period), \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
