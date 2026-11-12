import FNMNCore
import SwiftUI

struct AlbumTile: View {
    let album: AlbumSummary
    var pick: (() -> Void)?
    @Environment(WindowNavigation.self) private var navigation

    var body: some View {
        Button(action: open) {
            label
        }
        .buttonStyle(.plain)
        .modifier(AlbumTileBehavior(album: album))
        .modifier(AlbumZoomSource(route: pick == nil ? route : nil))
    }

    private var route: Route {
        switch album.grouping {
        case .albums: .album(album.name)
        case .publishers: .source(album.key)
        case .types, .months: .group(album.grouping, album.key)
        }
    }

    private func open() {
        if let pick {
            pick()
            return
        }
        navigation.open(route)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: -4) {
            AlbumFan(front: album.front)
                .aspectRatio(Tokens.tileAspect, contentMode: .fit)
            HStack(alignment: .firstTextBaseline) {
                Text(album.name).lineLimit(1)
                Spacer(minLength: 4)
                Text(album.count, format: .number).foregroundStyle(.secondary)
            }
            .font(.title3.weight(.black))
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
    }
}

private struct AlbumFan: View {
    let front: [LibraryItem]

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if front.isEmpty {
                    Image(systemName: "rectangle.stack")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .plate(cornerRadius: Tokens.tileRadius)
                } else {
                    ZStack {
                        ForEach(Array(front.enumerated().reversed()), id: \.element.id) { index, item in
                            card(item, place: place(index))
                        }
                    }
                }
            }
    }

    private struct Place {
        let degrees: Double
        let scale: CGFloat
        let offset: CGSize
    }

    private func place(_ index: Int) -> Place {
        Place(
            degrees: front.count == 1 ? -4 : Self.angles[index],
            scale: 0.86,
            offset: CGSize(width: Self.shifts[index], height: index == 0 ? 4 : -4)
        )
    }

    @ViewBuilder
    private func card(_ item: LibraryItem, place: Place) -> some View {
        let turned = TurnedRectangle(cornerRadius: Tokens.tileRadius, degrees: place.degrees, scale: place.scale, offset: place.offset)
        if let cover = item.cover {
            CoverImage(cover: cover, cornerRadius: Tokens.tileRadius)
                .scaleEffect(place.scale)
                .rotationEffect(.degrees(place.degrees))
                .offset(place.offset)
                .background { Color.clear.padding(3).plate(in: turned) }
        } else {
            Text(item.title)
                .font(.headline.weight(.black))
                .lineLimit(5)
                .padding(Tokens.tilePadding)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .scaleEffect(place.scale)
                .rotationEffect(.degrees(place.degrees))
                .offset(place.offset)
                .plate(in: turned)
        }
    }

    private static let angles: [Double] = [-4, 0, 6]
    private static let shifts: [CGFloat] = [-10, 0, 10]
}

private struct AlbumZoomSource: ViewModifier {
    let route: Route?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let route {
            content.zoomSource(of: route)
        } else {
            content
        }
    }
}

private struct AlbumTileBehavior: ViewModifier {
    let album: AlbumSummary
    @Environment(LibraryModel.self) private var library
    @Environment(LibraryDialogs.self) private var dialogs

    @ViewBuilder
    func body(content: Content) -> some View {
        if album.grouping == .albums {
            content
                .dropDestination(for: String.self) { ids, _ in
                    Task { await library.apply(.addToCollection(album.name, itemIDs: ids)) }
                    return !ids.isEmpty
                }
                .sensoryFeedback(.success, trigger: album.count) { old, new in new > old }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") { dialogs.send(.renameAlbum(album.name)) }
                    Button("Delete Collection", systemImage: "trash", role: .destructive) { dialogs.sendAfterMenu(.confirmAlbumDelete(album.name)) }
                }
        } else {
            content
        }
    }
}

struct GroupScreen: View {
    let grouping: LibraryGrouping
    let key: String
    @Environment(LibraryModel.self) private var library
    @State private var query = ""

    var body: some View {
        let found = library.queries.search(query, in: library.queries.items(in: grouping, key: key))
        ScrollView {
            ArrangedItems(items: found, scope: "group:\(grouping.rawValue):\(key)")
                .padding(.horizontal, Tokens.gutter)
        }
        .background(Tokens.canvas)
        .noResults(for: query, when: found.isEmpty)
        .screenSearch($query)
        .navigationTitle(library.queries.groupName(grouping, key: key))
        .task { library.apply(.openGroup(id: AlbumSummary.id(grouping, key))) }
    }
}

struct AlbumScreen: View {
    let name: String
    @Environment(LibraryModel.self) private var library
    @Environment(LibraryDialogs.self) private var dialogs
    @State private var query = ""

    var body: some View {
        let found = library.queries.search(query, in: library.queries.items(inAlbum: name))
        ScrollView {
            ArrangedItems(items: found, album: name, scope: "album:\(name)")
                .padding(.horizontal, Tokens.gutter)
        }
        .background(Tokens.canvas)
        .noResults(for: query, when: found.isEmpty)
        .screenSearch($query)
        .navigationTitle(name)
        .task { library.apply(.openGroup(id: AlbumSummary.id(.albums, name))) }
        .toolbar {
            Menu("More", systemImage: "ellipsis") {
                Button("Rename", systemImage: "pencil") { dialogs.send(.renameAlbum(name)) }
                Button("Delete Collection", systemImage: "trash", role: .destructive) { dialogs.sendAfterMenu(.confirmAlbumDelete(name)) }
            }
        }
    }
}

struct AlbumPicker: View {
    let itemID: String
    @Environment(LibraryModel.self) private var library
    @Environment(LibraryDialogs.self) private var dialogs

    var body: some View {
        NavigationStack {
            ScrollView {
                let current = Set(library.snapshot.albums(of: itemID))
                CardColumns(items: library.queries.albumSummaries.filter { !current.contains($0.name) }, idealWidth: 170) { album in
                    AlbumTile(album: album) {
                        dialogs.send(.dismiss)
                        Task { await library.apply(.addToCollection(album.name, itemIDs: [itemID])) }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
            }
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dialogs.send(.dismiss) }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Collection", systemImage: "plus") { dialogs.send(.nameAlbum(adding: itemID)) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct SourceScreen: View {
    let id: String
    @Environment(LibraryModel.self) private var library
    @State private var query = ""

    var body: some View {
        let items = library.queries.items(fromSource: id)
        let found = library.queries.search(query, in: items)
        ScrollView {
            ArrangedItems(items: found, scope: "source:\(id)").padding(.horizontal, Tokens.gutter)
        }
        .background(Tokens.canvas)
        .noResults(for: query, when: found.isEmpty)
        .screenSearch($query)
        .navigationTitle(items.first?.source?.name ?? "")
        .task { library.apply(.openGroup(id: AlbumSummary.id(.publishers, id))) }
        .toolbar {
            if let homepage = items.lazy.compactMap(\.source?.homepage).first {
                Link(destination: homepage) { Label("Open Site", systemImage: "arrow.up.right") }
            }
        }
    }
}

struct LinkSheet: View {
    @State var text: String
    @Environment(LibraryDialogs.self) private var dialogs
    @Environment(ImportJobs.self) private var imports
    @FocusState private var focused: Bool

    init(initial: String) {
        _text = State(initialValue: initial.isEmpty ? (UIPasteboard.general.url?.absoluteString ?? "") : initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("https://", text: $text)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit(add)
            }
            .navigationTitle("Add Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dialogs.send(.dismiss) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark", action: add).disabled(link == nil)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }

    private var link: URL? {
        URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { CaptureRoute.source(for: $0) != nil ? $0 : nil }
    }

    private func add() {
        guard let link else { return }
        imports.send(.submit(.link(link), id: UUID()))
        dialogs.send(.dismiss)
    }
}
