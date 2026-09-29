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

    /// The same outer size as a material's tile, so an album never looks smaller than what it holds.
    private var label: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumFan(covers: album.covers)
            HStack(alignment: .firstTextBaseline) {
                Text(album.name).lineLimit(1)
                Spacer(minLength: 4)
                Text(album.count, format: .number).foregroundStyle(.secondary)
            }
            .font(.title3.weight(.black))
            .padding(.horizontal, 4)
        }
        .aspectRatio(Tokens.tileAspect, contentMode: .fit)
    }
}

/// Up to three covers fanned out like a stack of photos; an empty album is a glass plate with a symbol.
private struct AlbumFan: View {
    let covers: [Cover]

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if covers.isEmpty {
                    Image(systemName: "rectangle.stack")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .plate(cornerRadius: Tokens.tileRadius)
                } else {
                    ZStack {
                        ForEach(Array(covers.enumerated().reversed()), id: \.offset) { index, cover in
                            CoverImage(cover: cover, cornerRadius: Tokens.tileRadius)
                                .overlay {
                                    RoundedRectangle(cornerRadius: Tokens.tileRadius, style: .continuous)
                                        .strokeBorder(.white.opacity(0.8), lineWidth: 2)
                                }
                                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                                .scaleEffect(0.86)
                                .rotationEffect(.degrees(angle(index)))
                                .offset(x: Self.shifts[index], y: index == 0 ? 6 : -4)
                        }
                    }
                }
            }
    }

    /// Even a single cover is turned a little, so an album never reads as a material's tile.
    private func angle(_ index: Int) -> Double {
        covers.count == 1 ? -5 : Self.angles[index]
    }

    private static let angles: [Double] = [2, -9, 9]
    private static let shifts: [CGFloat] = [0, -14, 14]
}

/// Dropping a tile adds the material to the album; the context menu renames or deletes it.
private struct AlbumTileBehavior: ViewModifier {
    let album: AlbumSummary
    @Environment(LibraryModel.self) private var library
    @Environment(LibraryDialogs.self) private var dialogs

    func body(content: Content) -> some View {
        content
            .dropDestination(for: String.self) { ids, _ in
                Task { for id in ids { await library.apply(.addToAlbum(album.name, itemID: id)) } }
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
                            Task { await library.apply(.addToAlbum(album.name, itemID: itemID)) }
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
