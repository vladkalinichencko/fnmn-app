import FNMNCore
import SwiftUI

struct LibraryScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ImportJobs.self) private var imports
    @Environment(WindowNavigation.self) private var navigation
    @Environment(LibraryDialogs.self) private var dialogs

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.library) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.sectionGap) {
                    let continued = library.snapshot.continueItems()
                    if !continued.isEmpty {
                        LibrarySection("Continue") { ItemGrid(items: continued) }
                    }
                    LibrarySection("Unsorted") {
                        LazyVGrid(columns: Tokens.grid, spacing: Tokens.gap) {
                            ForEach(imports.jobs.filter(\.addsMaterial)) { PreparingTile(job: $0) }
                            ForEach(library.snapshot.unsortedItems) { ItemTile(item: $0) }
                        }
                    }
                    LibrarySection("Albums") {
                        LazyVGrid(columns: Tokens.grid, spacing: Tokens.gap) {
                            ForEach(library.snapshot.albumSummaries) { AlbumTile(album: $0) }
                        }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, Tokens.sectionGap)
            }
            .background(Tokens.canvas)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { dialogs.send(.openSettings) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Add", systemImage: "plus") {
                        Button("Link", systemImage: "link") { dialogs.send(.addLink("")) }
                        Button("File", systemImage: "doc") { dialogs.send(.pickFile) }
                        Button("New Album", systemImage: "rectangle.stack.badge.plus") { dialogs.send(.nameAlbum(adding: nil)) }
                    }
                }
            }
        }
    }
}

/// A titled part of a screen with a large header, used by Library, Shelf and search.
struct LibrarySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.gap) {
            Text(title).font(Tokens.sectionTitle)
            content()
        }
    }
}
