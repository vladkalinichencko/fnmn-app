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
}

/// The window's own place in the app: its tab, the stack of each tab and the search text.
@MainActor @Observable
final class WindowNavigation {
    var tab = ShellTab.library
    var library: [Route] = []
    var shelf: [Route] = []
    var search: [Route] = []
    var query = ""

    /// Pushes onto the stack of the visible tab.
    func open(_ route: Route) {
        switch tab {
        case .library: library.append(route)
        case .shelf: shelf.append(route)
        case .search: search.append(route)
        }
    }

    /// Opens a route from outside the app on a fresh Library stack.
    func show(_ route: Route) {
        tab = .library
        library = [route]
    }
}

struct AppShell: View {
    @Environment(WindowNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
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
        .searchable(text: $navigation.query)
        .tabViewSearchActivation(.searchTabSelection)
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
        }
    }
}
