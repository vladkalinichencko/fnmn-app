import FNMNCore
import SwiftUI

/// SwiftUI also exports a `LibraryItem` (Xcode's view library); in this app the name means the material.
typealias LibraryItem = FNMNCore.LibraryItem

enum ShellTab: Hashable {
    case library, digest, shelf
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

/// Where the digest tab's stack can go: one post with its thread, and the sources the Mac reads.
enum DigestRoute: Hashable {
    case thread(String)
    case sources
}

extension Route {
    /// A material, an album, a publisher or a type grows out of its tile and needs no tabs.
    var hidesTabBar: Bool {
        switch self {
        case .item, .album, .source, .group: true
        case .annotations, .archive: false
        }
    }
}

extension DigestRoute {
    /// A thread is read on its own, so the tab bar goes while one is the top of the stack.
    var hidesTabBar: Bool {
        if case .thread = self {
            return true
        }
        return false
    }
}

enum PendingRoute: Equatable {
    case none
    case continueReading

    func arriving() -> PendingRoute {
        .continueReading
    }

    func consume(_ phase: LibraryPhase, continued: () -> Route?) -> (PendingRoute, Route?) {
        guard self == .continueReading, phase == .ready else {
            return (self, nil)
        }
        return (.none, continued())
    }
}

/// The window's own place in the app: its tab and the stack of each tab.
@MainActor @Observable
final class WindowNavigation {
    var tab = ShellTab.library
    var library: [Route] = []
    var digest: [DigestRoute] = []
    var shelf: [Route] = []
    var pending = PendingRoute.none

    /// Pushes onto the stack of the visible tab.
    func open(_ route: Route) {
        switch tab {
        case .library: library.append(route)
        case .digest: break
        case .shelf: shelf.append(route)
        }
    }

    /// Pushes onto the digest tab's stack.
    func open(_ route: DigestRoute) {
        digest.append(route)
    }

    /// Opens a route from outside the app on a fresh Library stack.
    func show(_ route: Route) {
        tab = .library
        library = [route]
    }

    func showPending(phase: LibraryPhase, continued: () -> Route?) {        let (rest, route) = pending.consume(phase, continued: continued)
        pending = rest
        if let route {
            show(route)
        }
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
    func zoomSource(of id: some Hashable & Sendable) -> some View {
        modifier(ZoomSourceModifier(id: id))
    }
}

private struct ZoomSourceModifier: ViewModifier {
    let id: AnyHashable
    @Environment(\.zoomNamespace) private var namespace

    init(id: some Hashable & Sendable) {
        self.id = AnyHashable(id)
    }

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
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
            Tab("Digest", systemImage: "newspaper", value: ShellTab.digest) {
                DigestScreen()
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

/// A tab's stack: the root screen, the screens its path opens, and whether the bar hides on the top one. It
/// follows the path, not the screen's own appearance, which a swipe back with the zoom transition does not
/// always report.
struct RouteStack<Path: Hashable, Root: View, Destination: View>: View {
    @Binding var path: [Path]
    let hidesTabBar: (Path) -> Bool
    let root: Root
    let destination: (Path) -> Destination

    init(
        path: Binding<[Path]>,
        hidesTabBar: @escaping (Path) -> Bool,
        @ViewBuilder root: () -> Root,
        @ViewBuilder destination: @escaping (Path) -> Destination
    ) {
        _path = path
        self.hidesTabBar = hidesTabBar
        self.root = root()
        self.destination = destination
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: Path.self) { destination($0) }
        }
        .toolbarVisibility(path.last.map(hidesTabBar) ?? false ? .hidden : .automatic, for: .tabBar)
    }
}

/// A material, an album, a publisher or a type grows out of its tile.
struct RouteScreen: View {
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
