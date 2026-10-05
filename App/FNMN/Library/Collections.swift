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

    /// The fan takes a whole tile's shape, so an album never looks smaller than what it holds; the name goes under it.
    /// The fan's cards are shrunk inside that shape, which leaves about twelve points under them, so the name moves
    /// up into that space: the gap from the fan to its name stays smaller than the grid's gap below the name, and the
    /// name reads as the fan's. The whole tile takes the tap, so a finger between the turned cards still opens the album.
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

/// Up to three materials fanned out like a stack of photos: a cover where there is one, the title on a plate where not.
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

    /// Where a card lies in the fan: its turn, its size and how far it is moved from the middle.
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

    /// A picture is laid down like a photo, with a shadow under it and a plate of glass behind it, which a picture
    /// with transparent parts shows through.
    /// A title on glass starts a little lower than on a tile, clear of the turned plate's corner.
    /// A title lies on glass, and glass under a transform spreads past its frame, so the glass turns its shape instead.
    @ViewBuilder
    private func card(_ item: LibraryItem, place: Place) -> some View {
        let turned = TurnedRectangle(cornerRadius: Tokens.tileRadius, degrees: place.degrees, scale: place.scale, offset: place.offset)
        if let cover = item.cover {
            CoverImage(cover: cover, cornerRadius: Tokens.tileRadius)
                .scaleEffect(place.scale)
                .rotationEffect(.degrees(place.degrees))
                .offset(place.offset)
                .background { Color.clear.plate(in: turned) }
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
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

    /// Even a single card is turned a little, so an album never reads as a material's tile.
    private static let angles: [Double] = [2, -7, 7]
    private static let shifts: [CGFloat] = [0, -10, 10]
}

/// The tile its screen grows out of; the picker's tiles only choose an album, so they open nothing.
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

/// Dropping a tile adds the material to the album; the context menu renames or deletes it.
private struct AlbumTileBehavior: ViewModifier {
    let album: AlbumSummary
    @Environment(LibraryModel.self) private var library
    @Environment(LibraryDialogs.self) private var dialogs

    @ViewBuilder
    func body(content: Content) -> some View {
        if album.grouping == .albums {
            content
                .dropDestination(for: String.self) { ids, _ in
                    Task { await library.apply(.addToAlbum(album.name, itemIDs: ids)) }
                    return !ids.isEmpty
                }
                .sensoryFeedback(.success, trigger: album.count) { old, new in new > old }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") { dialogs.send(.renameAlbum(album.name)) }
                    Button("Delete Collection", systemImage: "trash", role: .destructive) { dialogs.send(.confirmAlbumDelete(album.name)) }
                }
        } else {
            content
        }
    }
}

/// The materials of one type or month of the Collections section.
struct GroupScreen: View {
    let grouping: LibraryGrouping
    let key: String
    @Environment(LibraryModel.self) private var library
    @State private var query = ""

    var body: some View {
        let found = library.snapshot.items(matching: query, among: library.snapshot.items(in: grouping, key: key))
        ScrollView {
            ArrangedItems(items: found, scope: "group:\(grouping.rawValue):\(key)")
                .padding(.horizontal, Tokens.gutter)
        }
        .background(Tokens.canvas)
        .noResults(for: query, when: found.isEmpty)
        .screenSearch($query)
        .navigationTitle(library.snapshot.groupName(grouping, key: key))
        .task { library.apply(.openGroup(id: AlbumSummary.id(grouping, key))) }
    }
}

struct AlbumScreen: View {
    let name: String
    @Environment(LibraryModel.self) private var library
    @Environment(LibraryDialogs.self) private var dialogs
    @State private var query = ""

    var body: some View {
        let found = library.snapshot.items(matching: query, among: library.snapshot.items(inAlbum: name))
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
                Button("Delete Collection", systemImage: "trash", role: .destructive) { dialogs.send(.confirmAlbumDelete(name)) }
            }
        }
    }
}

/// Add to Album: the albums as tiles, as in Photos, and a new one.
struct AlbumPicker: View {
    let itemID: String
    @Environment(LibraryModel.self) private var library
    @Environment(LibraryDialogs.self) private var dialogs

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Tokens.grid, spacing: Tokens.gap) {
                    // The collections the material is already in are not offered again.
                    let current = library.snapshot.albums(of: itemID)
                    ForEach(library.snapshot.albumSummaries.filter { !current.contains($0.name) }) { album in
                        AlbumTile(album: album) {
                            dialogs.send(.dismiss)
                            Task { await library.apply(.addToAlbum(album.name, itemIDs: [itemID])) }
                        }
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

/// Everything saved from one author, blog or channel, and the way to its home page.
struct SourceScreen: View {
    let id: String
    @Environment(LibraryModel.self) private var library
    @State private var query = ""

    var body: some View {
        let items = library.snapshot.items(fromSource: id)
        let found = library.snapshot.items(matching: query, among: items)
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

/// Add → Link: one field, the pasteboard's link already in it.
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
