import FNMNCore
import SwiftUI

/// SwiftUI also exports a `LibraryItem` (Xcode's view library); in this app the name means the material.
typealias LibraryItem = FNMNCore.LibraryItem

enum ShellTab: Hashable {
    case library, shelf, search
}

/// Where a tab's navigation stack can go.
enum Route: Hashable {
    case item(String, piece: Int? = nil)
    case album(String)
    case source(String)
    case annotations
    case archive
}

/// The window's own place in the app: its tab, the stack of each tab, the stack above all the tabs and the search text.
@MainActor @Observable
final class WindowNavigation {
    var tab = ShellTab.library
    var library: [Route] = []
    var shelf: [Route] = []
    var search: [Route] = []
    /// What is pushed over the whole tab view: a material and whatever it opens. The tab bar is part of the screen
    /// below, so it slides away with it on the way in and comes back with it on the way out.
    var covering: [Route] = []
    var query = ""

    /// Pushes a material, or anything opened from a screen above the tabs, over the tabs; everything else goes
    /// onto the stack of the visible tab.
    func open(_ route: Route) {
        if case .item = route {
            covering.append(route)
            return
        }
        if !covering.isEmpty {
            covering.append(route)
            return
        }
        switch tab {
        case .library: library.append(route)
        case .shelf: shelf.append(route)
        case .search: search.append(route)
        }
    }

    /// Opens a route from outside the app on a fresh Library stack.
    func show(_ route: Route) {
        tab = .library
        library = []
        covering = [route]
    }
}

struct AppShell: View {
    @Environment(WindowNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.covering) {
            TabView(selection: $navigation.tab) {
                Tab("Library", systemImage: "books.vertical", value: ShellTab.library) {
                    LibraryScreen()
                }
                Tab("Shelf", systemImage: "bookmark", value: ShellTab.shelf) {
                    ShelfScreen()
                }
                Tab(value: ShellTab.search, role: .search) {
                    SearchScreen()
                }
            }
            .tabViewSearchActivation(.searchTabSelection)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                RouteScreen(route: route)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .libraryDialogs()
    }
}

/// A tab's stack: every screen of the library is reachable from any tab the same way.
struct RouteStack<Root: View>: View {
    @Binding var path: [Route]
    @ViewBuilder let root: () -> Root

    var body: some View {
        NavigationStack(path: $path) {
            root()
                .navigationDestination(for: Route.self) { route in
                    RouteScreen(route: route)
                }
        }
    }
}

/// A material opens with the standard push: a zoom transition would take the reader's pinch for closing it.
private struct RouteScreen: View {
    let route: Route

    var body: some View {
        switch route {
        case let .item(id, piece):
            ItemScreen(itemID: id, startPiece: piece)
        case let .album(name):
            AlbumScreen(name: name)
        case let .source(name):
            SourceScreen(name: name)
        case .annotations:
            AnnotationsScreen()
        case .archive:
            ArchiveScreen()
        }
    }
}
