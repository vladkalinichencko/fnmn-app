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
    }

    private func open() {
        if let pick { pick() } else { navigation.open(.album(album.name)) }
    }

    /// The fan takes a whole tile's shape, so an album never looks smaller than what it holds; the name goes under it.
    private var label: some View {
        VStack(alignment: .leading, spacing: 10) {
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

    /// A picture is laid down like a photo, with a white edge, a shadow inside and a deeper one under it.
    /// The picture, its inner shadow and its edge are drawn once into one texture, so scrolling moves a finished
    /// image instead of blurring the edge again; the shadow under it stays outside, where the texture would clip it.
    /// A title lies on glass, and glass under a transform spreads past its frame, so the glass turns its shape instead.
    @ViewBuilder
    private func card(_ item: LibraryItem, place: Place) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.tileRadius, style: .continuous)
        if let cover = item.cover {
            CoverImage(cover: cover, cornerRadius: Tokens.tileRadius)
                .overlay {
                    shape.stroke(.black.opacity(0.35), lineWidth: 8).blur(radius: 6).clipShape(shape)
                }
                .overlay { shape.strokeBorder(.white.opacity(0.85), lineWidth: 2) }
                .drawingGroup()
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
                .scaleEffect(place.scale)
                .rotationEffect(.degrees(place.degrees))
                .offset(place.offset)
        } else {
            Text(item.title)
                .font(.headline.weight(.black))
                .lineLimit(5)
                .padding(Tokens.tilePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .scaleEffect(place.scale)
                .rotationEffect(.degrees(place.degrees))
                .offset(place.offset)
                .plate(in: TurnedRectangle(cornerRadius: Tokens.tileRadius, degrees: place.degrees, scale: place.scale, offset: place.offset))
        }
    }

    /// Even a single card is turned a little, so an album never reads as a material's tile.
    private static let angles: [Double] = [2, -7, 7]
    private static let shifts: [CGFloat] = [0, -10, 10]
}

/// Dropping a tile adds the material to the album; the context menu renames or deletes it.
private struct AlbumTileBehavior: ViewModifier {
    let album: AlbumSummary
    @Environment(LibraryModel.self) private var library
    @Environment(LibraryDialogs.self) private var dialogs

    func body(content: Content) -> some View {
        content
            .dropDestination(for: String.self) { ids, _ in
                Task { await library.apply(.addToAlbum(album.name, itemIDs: ids)) }
                return !ids.isEmpty
            }
            .sensoryFeedback(.success, trigger: album.count) { old, new in new > old }
            .contextMenu {
                Button("Rename", systemImage: "pencil") { dialogs.send(.renameAlbum(album.name)) }
                Button("Delete Album", systemImage: "trash", role: .destructive) { dialogs.send(.confirmAlbumDelete(album.name)) }
            }
    }
}

struct AlbumScreen: View {
    let name: String
    @Environment(LibraryModel.self) private var library
    @Environment(LibraryDialogs.self) private var dialogs

    var body: some View {
        ScrollView {
            ItemGrid(items: library.snapshot.items(inAlbum: name), album: name)
                .padding(.horizontal, Tokens.gutter)
        }
        .background(Tokens.canvas)
        .navigationTitle(name)
        .toolbar {
            Menu("More", systemImage: "ellipsis") {
                Button("Rename", systemImage: "pencil") { dialogs.send(.renameAlbum(name)) }
                Button("Delete Album", systemImage: "trash", role: .destructive) { dialogs.send(.confirmAlbumDelete(name)) }
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
                    ForEach(library.snapshot.albumSummaries) { album in
                        AlbumTile(album: album) {
                            dialogs.send(.dismiss)
                            Task { await library.apply(.addToAlbum(album.name, itemIDs: [itemID])) }
                        }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
            }
            .navigationTitle("Add to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dialogs.send(.dismiss) }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Album", systemImage: "plus") { dialogs.send(.nameAlbum(adding: itemID)) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Everything saved from one author, blog or channel, and the way to its home page.
struct SourceScreen: View {
    let name: String
    @Environment(LibraryModel.self) private var library

    var body: some View {
        let items = library.snapshot.items(fromSource: name)
        ScrollView {
            ItemGrid(items: items).padding(.horizontal, Tokens.gutter)
        }
        .background(Tokens.canvas)
        .navigationTitle(name)
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
