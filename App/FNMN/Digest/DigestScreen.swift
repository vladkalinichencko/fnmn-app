import FNMNCore
import SwiftUI

struct DigestScreen: View {
    @Environment(DigestModel.self) private var digests
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @AppStorage(ReaderAppearance.columnKey) private var column = ReaderColumn.regular
    @State private var query = ""
    @State private var mediaPresenter = MediaPresenter()
    @Namespace private var mediaZoom

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.digest) {
            content
                .modifier(ReaderAppearanceModifier())
                .screenSearch($query)
                .navigationTitle("Digest")
                .appRefresh(title: "Digest")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Sources", systemImage: "antenna.radiowaves.left.and.right") {
                            navigation.digest.append(.sources)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Display", systemImage: "textformat") {
                            ReaderAppearanceControls()
                        }
                    }
                }
                .task { await digests.sync(folder: library.cloudFolder) }
        } destination: { route in
            switch route {
            case let .thread(id):
                ThreadScreen(postID: id)
                    .zoomDestination(of: id)
                    .interactiveOnlyAtStackTop(route)
            case .sources:
                SourcesScreen()
                    .interactiveOnlyAtStackTop(route)
            }
        }
        .environment(\.mediaPresenter, mediaPresenter)
        .environment(\.mediaZoom, mediaZoom)
        .presentsMedia(mediaPresenter)
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
            ForEach(digests.digests) { digest in
                digestHeader(digest)
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections(of: digest)
                } else {
                    results(of: digest)
                }
            }
        }
    }

    private func digestHeader(_ digest: Digest) -> some View {
        let end = digest.package.window.to
        let period = Calendar.current.component(.hour, from: end) < 16 ? "Morning" : "Evening"
        return Text("\(period), \(end.formatted(.dateTime.month(.abbreviated).day()))")
            .font(.largeTitle.weight(.bold))
            .padding(.horizontal, Tokens.gutter)
            .padding(.top, Tokens.sectionGap)
    }

    private func sections(of digest: Digest) -> some View {
        LazyVStack(alignment: .leading, spacing: Tokens.sectionGap) {
            ForEach(digest.package.sections(hidden: digests.hidden)) { network in
                VStack(alignment: .leading, spacing: Tokens.gap) {
                    Text(network.network.name)
                        .font(.title2.weight(.bold))
                    ForEach(network.topics) { topic in
                        VStack(alignment: .leading, spacing: Tokens.gap) {
                            Text(topic.folder.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            CardColumns(items: topic.posts, idealWidth: column.cardWidth, height: PostCard.estimatedHeight, separates: true) { post in
                                PostCard(post: post, digest: digest, opensThread: post.hasThread)
                            }
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
        return CardColumns(items: found, idealWidth: column.cardWidth, height: PostCard.estimatedHeight, separates: true) { post in
            PostCard(post: post, digest: digest, opensThread: post.hasThread)
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.bottom, Tokens.sectionGap)
        .noResults(for: query, when: found.isEmpty)
    }
}

private extension ReaderColumn {
    var cardWidth: CGFloat {
        switch self {
        case .narrow: 280
        case .regular: 330
        case .wide: 420
        }
    }
}
