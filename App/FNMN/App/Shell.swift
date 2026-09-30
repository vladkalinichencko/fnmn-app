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

extension EnvironmentValues {
    /// The namespace a material's tile and the material's screen share, so the screen grows out of the tile.
    @Entry var zoomNamespace: Namespace.ID?
}

extension View {
    /// Makes a tile the place its material's screen opens from and closes back to.
    @ViewBuilder
    func zoomSource(of itemID: String, cornerRadius: CGFloat) -> some View {
        modifier(ZoomSourceModifier(itemID: itemID, cornerRadius: cornerRadius))
    }
}

private struct ZoomSourceModifier: ViewModifier {
    let itemID: String
    let cornerRadius: CGFloat
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: itemID, in: namespace) {
                $0.clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
        }
    }
}

private struct ZoomDestinationModifier: ViewModifier {
    let itemID: String
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: itemID, in: namespace))
        } else {
            content
        }
    }
}

struct AppShell: View {
    @Environment(WindowNavigation.self) private var navigation
    @Namespace private var zoom

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
        .tabViewSearchActivation(.searchTabSelection)
        .environment(\.zoomNamespace, zoom)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .libraryDialogs()
    }
}

/// A tab's stack: every screen of the library is reachable from any tab the same way.
struct RouteStack<Root: View>: View {
    @Binding var path: [Route]
    @ViewBuilder let root: () -> Root

    /// A material needs no tabs, so the bar is hidden while one is the top of the stack; it follows the path,
    /// not the screen's own appearance, which a swipe back with the zoom transition does not always report.
    private var showsMaterial: Bool {
        if case .item? = path.last { true } else { false }
    }

    var body: some View {
        NavigationStack(path: $path) {
            root()
                .navigationDestination(for: Route.self) { route in
                    RouteScreen(route: route)
                }
        }
        .toolbarVisibility(showsMaterial ? .hidden : .automatic, for: .tabBar)
    }
}

/// A material grows out of its tile.
private struct RouteScreen: View {
    let route: Route

    var body: some View {
        switch route {
        case let .item(id, piece):
            ItemScreen(itemID: id, startPiece: piece)
                .modifier(ZoomDestinationModifier(itemID: id))
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
