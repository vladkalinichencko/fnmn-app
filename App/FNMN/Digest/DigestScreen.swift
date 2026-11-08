import FNMNCore
import SwiftUI

/// The digest tab: the newest delivery as a magazine, one column on a phone and as many as the width holds on
/// an iPad, sectioned by the folders the subscriptions and the classifier name. The search field narrows the
/// open digest; the Sources button shows what the Mac reads.
struct DigestScreen: View {
    @Environment(DigestModel.self) private var digests
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @State private var query = ""

    var body: some View {
        @Bindable var navigation = navigation
        DigestStack(path: $navigation.digest) {
            content
                .background(Tokens.canvas)
                .screenSearch($query)
                .navigationTitle("Digest")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Sources", systemImage: "antenna.radiowaves.left.and.right") {
                            navigation.digest.append(.sources)
                        }
                    }
                    if digests.syncState == .syncing {
                        ToolbarItem(placement: .topBarTrailing) {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .task { await digests.sync(folder: library.cloudFolder) }
        }
    }

    @ViewBuilder private var content: some View {
        switch digests.state {
        case .idle, .loading:
            Loading()
        case let .failed(message):
            ContentUnavailableView {
                Label("Digest unavailable", systemImage: "newspaper")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await digests.sync(folder: library.cloudFolder) }
                }
            }
        case .ready where digests.current == nil:
            ContentUnavailableView {
                Label("No digest yet", systemImage: "newspaper")
            } description: {
                Text(digests.lastError ?? "The Mac builds one twice a day and leaves it in the FNMN folder.")
            } actions: {
                Button("Refresh") {
                    Task { await digests.sync(folder: library.cloudFolder) }
                }
            }
        case .ready:
            magazine
        }
    }

    private var magazine: some View {
        ScrollView {
            if let error = digests.lastError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Retry") {
                        Task { await digests.sync(folder: library.cloudFolder) }
                    }
                    .font(.caption)
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, Tokens.gap)
            }
            if let digest = digests.current {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections(of: digest)
                } else {
                    results(of: digest)
                }
            }
        }
        .refreshable {
            await digests.sync(folder: library.cloudFolder)
        }
    }

    private func sections(of digest: Digest) -> some View {
        LazyVStack(alignment: .leading, spacing: Tokens.sectionGap) {
            ForEach(digest.package.sections(labels: digests.labels, hidden: digests.hidden)) { section in
                LibrarySection(section.folder.uppercased()) {
                    LazyVGrid(columns: Self.columns, spacing: Tokens.gap) {
                        ForEach(section.posts) { post in
                            PostCard(post: post, digest: digest, read: digests.seen.contains(post.id))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.bottom, Tokens.sectionGap)
    }

    private func results(of digest: Digest) -> some View {
        let found = digests.posts(matching: query, in: digest.package)
        return LazyVGrid(columns: Self.columns, spacing: Tokens.gap) {
            ForEach(found) { post in
                PostCard(post: post, digest: digest, read: digests.seen.contains(post.id))
            }
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.bottom, Tokens.sectionGap)
        .noResults(for: query, when: found.isEmpty)
    }

    /// A card is never narrower than about 330 points, so a phone holds one and an iPad two or three.
    private static let columns = [GridItem(.adaptive(minimum: 330, maximum: 640), spacing: Tokens.gap)]
}

/// The digest tab's own stack: a thread and the sources push over the magazine, and the tab bar hides while a
/// thread is the top of the stack, as it does over a material.
private struct DigestStack<Root: View>: View {
    @Binding var path: [DigestRoute]
    @ViewBuilder let root: () -> Root

    private var showsThread: Bool {
        if case .thread? = path.last {
            return true
        }
        return false
    }

    var body: some View {
        NavigationStack(path: $path) {
            root()
                .navigationDestination(for: DigestRoute.self) { route in
                    switch route {
                    case let .thread(id):
                        ThreadScreen(postID: id)
                    case .sources:
                        SourcesScreen()
                    }
                }
        }
        .toolbarVisibility(showsThread ? .hidden : .automatic, for: .tabBar)
    }
}
