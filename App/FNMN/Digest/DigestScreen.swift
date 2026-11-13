import FNMNCore
import SwiftUI

struct DigestScreen: View {
    @Environment(DigestModel.self) private var digests
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @Environment(LibraryDialogs.self) private var dialogs
    @AppStorage(ReaderAppearance.columnKey) private var column = ReaderColumn.regular
    @State private var query = ""
    @State private var mediaPresenter = MediaPresenter()
    @Namespace private var mediaZoom

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.digest) {
            content
                .searchResults(query: $query, active: digests.state == .ready) { needle in
                    DigestSearchResults(query: needle) { post in
                        navigation.digestPost = post.id
                        query = ""
                    }
                }
                .modifier(ReaderAppearanceModifier())
                .screenSearch($query)
                .navigationTitle("Digest")
                .appRefresh(title: "Digest")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape") {
                            dialogs.send(.openSettings(.digest))
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
            }
        }
        .presentsMedia(mediaPresenter)
        .environment(\.mediaPresenter, mediaPresenter)
        .environment(\.mediaZoom, mediaZoom)
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
        ScrollViewReader { proxy in
            ScrollView {
                ForEach(digests.digests) { digest in
                    let networks = digest.package.sections(hidden: digests.hidden)
                    digestHeader(digest, networks: networks)
                    sections(of: digest, networks: networks)
                }
            }
            .onAppear {
                revealPendingPost(using: proxy)
            }
            .onChange(of: navigation.digestPost) { _, _ in
                revealPendingPost(using: proxy)
            }
            .onChange(of: digests.digests.map(\.id)) { _, _ in
                revealPendingPost(using: proxy)
            }
        }
    }

    private func revealPendingPost(using proxy: ScrollViewProxy) {
        guard let id = navigation.digestPost, digests.post(id) != nil else {
            return
        }
        navigation.digestPost = nil
        proxy.scrollTo(id, anchor: .center)
    }

    private func digestHeader(_ digest: Digest, networks: [DigestPackage.NetworkSection]) -> some View {
        let end = digest.package.window.to
        let period = Calendar.current.component(.hour, from: end) < 16 ? "Morning" : "Evening"
        let fold: DigestFold = .digest(digest.id)
        let hidden = networks.reduce(0) { $0 + $1.topics.reduce(0) { $0 + $1.posts.count } }
        return FoldableHeader(
            title: "\(period), \(end.formatted(.dateTime.month(.abbreviated).day()))",
            font: .largeTitle.weight(.bold),
            fold: fold,
            hidden: hidden,
            collapsed: fold.collapsed(in: digests.folded)
        )
        .padding(.horizontal, Tokens.gutter)
        .padding(.top, Tokens.sectionGap)
    }

    private func sections(of digest: Digest, networks: [DigestPackage.NetworkSection]) -> some View {
        let digestFold: DigestFold = .digest(digest.id)
        return LazyVStack(alignment: .leading, spacing: Tokens.sectionGap) {
            if !digestFold.collapsed(in: digests.folded) {
                ForEach(networks) { network in
                    networkSection(of: network, in: digest)
                }
            }
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.bottom, Tokens.sectionGap)
    }

    private func networkSection(of network: DigestPackage.NetworkSection, in digest: Digest) -> some View {
        let fold: DigestFold = .network(digest: digest.id, network: network.network)
        let collapsed = fold.collapsed(in: digests.folded)
        let hidden = network.topics.reduce(0) { $0 + $1.posts.count }
        return VStack(alignment: .leading, spacing: Tokens.gap) {
            FoldableHeader(
                title: network.network.name,
                font: .title2.weight(.bold),
                fold: fold,
                hidden: hidden,
                collapsed: collapsed
            )
            if !collapsed {
                ForEach(network.topics) { topic in
                    topicSection(of: topic, network: network.network, in: digest)
                }
            }
        }
    }

    private func topicSection(of topic: DigestPackage.TopicSection, network: DigestPackage.Network, in digest: Digest) -> some View {
        let fold: DigestFold = .topic(digest: digest.id, network: network, folder: topic.folder)
        let collapsed = fold.collapsed(in: digests.folded)
        return VStack(alignment: .leading, spacing: Tokens.gap) {
            FoldableHeader(
                title: topic.folder.uppercased(),
                font: .caption.weight(.semibold),
                secondary: true,
                fold: fold,
                hidden: topic.posts.count,
                collapsed: collapsed
            )
            if !collapsed {
                CardColumns(items: topic.posts, idealWidth: column.cardWidth, height: PostCard.estimatedHeight, separates: true) { post in
                    PostCard(post: post, digest: digest, opensThread: post.hasThread)
                        .id(post.id)
                }
            }
        }
    }

}

private struct FoldableHeader: View {
    let title: String
    var font: Font = .body
    var secondary = false
    let fold: DigestFold
    let hidden: Int
    let collapsed: Bool
    @Environment(DigestModel.self) private var digests

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.gap) {
            Text(title)
                .font(font)
            Spacer(minLength: Tokens.gap)
            if collapsed, hidden > 0 {
                Text(hidden, format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .transition(.blurReplace)
            }
            if hidden > 0 {
                DisclosureChevron(open: !collapsed, width: 18)
            }
        }
        .foregroundStyle(secondary ? .secondary : .primary)
        .animation(.snappy(duration: 0.22), value: collapsed)
        .contentShape(.rect)
        .onTapGesture { digests.toggleFold(fold) }
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
