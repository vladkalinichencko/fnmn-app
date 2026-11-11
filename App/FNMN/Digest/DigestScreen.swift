import FNMNCore
import SwiftUI

struct DigestScreen: View {
    @Environment(DigestModel.self) private var digests
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @State private var query = ""

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.digest, hidesTabBar: { $0.hidesTabBar }) {
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
                                .progressViewStyle(GraySpinner())
                        }
                    }
                }
                .task { await digests.sync(folder: library.cloudFolder) }
        } destination: { route in
            switch route {
            case let .thread(id):
                ThreadScreen(postID: id)
                    .interactiveOnlyAtStackTop(route)
            case .sources:
                SourcesScreen()
                    .interactiveOnlyAtStackTop(route)
            }
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
        let found = digest.package.posts(matching: query, hidden: digests.hidden)
        return LazyVGrid(columns: Self.columns, spacing: Tokens.gap) {
            ForEach(found) { post in
                PostCard(post: post, digest: digest, read: digests.seen.contains(post.id))
            }
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.bottom, Tokens.sectionGap)
        .noResults(for: query, when: found.isEmpty)
    }

    private static let columns = [GridItem(.adaptive(minimum: 330, maximum: 640), spacing: Tokens.gap)]
}
