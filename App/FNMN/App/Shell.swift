import FNMNCore
import SwiftUI

/// SwiftUI also exports a `LibraryItem` (Xcode's view library); in this app the name means the material.
typealias LibraryItem = FNMNCore.LibraryItem

enum ShellTab: Hashable {
    case library, shelf
}

/// Where a tab's navigation stack can go.
enum Route: Hashable {
    case item(String, piece: Int? = nil)
    case album(String)
    case source(String)
    /// A type or a month of the Collections section; albums and publishers have routes of their own.
    case group(LibraryGrouping, String)
    case annotations
    case archive
}

/// The window's own place in the app: its tab and the stack of each tab.
@MainActor @Observable
final class WindowNavigation {
    var tab = ShellTab.library
    var library: [Route] = []
    var shelf: [Route] = []

    /// Pushes onto the stack of the visible tab.
    func open(_ route: Route) {
        switch tab {
        case .library: library.append(route)
        case .shelf: shelf.append(route)
        }
    }

    /// Opens a route from outside the app on a fresh Library stack.
    func show(_ route: Route) {
        tab = .library
        library = [route]
    }
}

extension EnvironmentValues {
    /// The namespace a tile and the screen it opens share, so the screen grows out of the tile.
    @Entry var zoomNamespace: Namespace.ID?
}

extension View {
    /// Makes a tile the place its screen opens from and closes back to. A material's tile is named by the
    /// material's id, an album's or a publisher's by the route it opens.
    @ViewBuilder
    func zoomSource(of id: some Hashable & Sendable, cornerRadius: CGFloat) -> some View {
        modifier(ZoomSourceModifier(id: id, cornerRadius: cornerRadius))
    }
}

private struct ZoomSourceModifier: ViewModifier {
    let id: AnyHashable
    let cornerRadius: CGFloat
    @Environment(\.zoomNamespace) private var namespace

    init(id: some Hashable & Sendable, cornerRadius: CGFloat) {
        self.id = AnyHashable(id)
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) {
                $0.clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
        }
    }
}

private struct ZoomDestinationModifier: ViewModifier {
    let id: AnyHashable
    @Environment(\.zoomNamespace) private var namespace

    init(id: some Hashable & Sendable) {
        self.id = AnyHashable(id)
    }

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
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
        }
        .environment(\.zoomNamespace, zoom)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .libraryDialogs()
    }
}

/// A tab's stack: every screen of the library is reachable from any tab the same way.
struct RouteStack<Root: View>: View {
    @Binding var path: [Route]
    @ViewBuilder let root: () -> Root

    /// A material, an album, a publisher or a type grows out of its tile and needs no tabs, so the bar is hidden
    /// while one is the top of the stack; it follows the path, not the screen's own appearance, which a swipe
    /// back with the zoom transition does not always report.
    private var showsMaterial: Bool {
        switch path.last {
        case .item?, .album?, .source?, .group?: true
        case .annotations?, .archive?, nil: false
        }
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

/// A material, an album, a publisher or a type grows out of its tile.
private struct RouteScreen: View {
    let route: Route

    var body: some View {
        switch route {
        case let .item(id, piece):
            ItemScreen(itemID: id, startPiece: piece)
                .modifier(ZoomDestinationModifier(id: id))
        case let .album(name):
            AlbumScreen(name: name)
                .modifier(ZoomDestinationModifier(id: route))
        case let .source(id):
            SourceScreen(id: id)
                .modifier(ZoomDestinationModifier(id: route))
        case let .group(grouping, key):
            GroupScreen(grouping: grouping, key: key)
                .modifier(ZoomDestinationModifier(id: route))
        case .annotations:
            AnnotationsScreen()
        case .archive:
            ArchiveScreen()
        }
    }
}
