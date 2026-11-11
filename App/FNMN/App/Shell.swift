import FNMNCore
import SwiftUI

typealias LibraryItem = FNMNCore.LibraryItem

enum ShellTab: Hashable {
    case library, digest, shelf
}

enum Route: Hashable {
    case item(String, piece: Int? = nil, seconds: Double? = nil)
    case album(String)
    case source(String)
    case group(LibraryGrouping, String)
    case annotations
    case archive
}

enum DigestRoute: Hashable {
    case thread(String)
    case sources
}

extension Route {
    var hidesTabBar: Bool {
        switch self {
        case .item, .album, .source, .group: true
        case .annotations, .archive: false
        }
    }
}

extension DigestRoute {
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

    func consume(_ phase: LibraryPhase, continued: () -> Route?) -> (PendingRoute, Route?) {
        guard self == .continueReading, phase == .ready else {
            return (self, nil)
        }
        return (.none, continued())
    }
}

@MainActor @Observable
final class WindowNavigation {
    var tab = ShellTab.library
    var library: [Route] = []
    var digest: [DigestRoute] = []
    var shelf: [Route] = []
    var pending = PendingRoute.none
    var pendingItem: Route?

    func open(_ route: Route) {
        switch tab {
        case .library: library.append(route)
        case .digest: break
        case .shelf: shelf.append(route)
        }
    }

    func open(_ route: DigestRoute) {
        digest.append(route)
    }

    func show(_ route: Route) {
        tab = .library
        library = [route]
    }

    func showPending(phase: LibraryPhase, continued: () -> Route?) {
        let (rest, route) = pending.consume(phase, continued: continued)
        pending = rest
        if let route {
            show(route)
        }
    }
}

extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID?
    @Entry var stackTop: AnyHashable?
}

extension View {
    @ViewBuilder
    func zoomSource(of id: some Hashable & Sendable) -> some View {
        modifier(ZoomSourceModifier(id: id))
    }

    func interactiveOnlyAtStackTop(_ route: some Hashable) -> some View {
        modifier(StackTopInteraction(route: AnyHashable(route)))
    }
}

private struct StackTopInteraction: ViewModifier {
    let route: AnyHashable
    @Environment(\.stackTop) private var stackTop

    func body(content: Content) -> some View {
        content.allowsHitTesting(stackTop == route)
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
        .environment(\.stackTop, path.last.map { AnyHashable($0) })
        .toolbarVisibility(path.last.map(hidesTabBar) ?? false ? .hidden : .automatic, for: .tabBar)
    }
}

struct RouteScreen: View {
    let route: Route

    var body: some View {
        content
            .interactiveOnlyAtStackTop(route)
    }

    @ViewBuilder private var content: some View {
        switch route {
        case let .item(id, piece, seconds):
            ItemScreen(itemID: id, startPiece: piece, startSeconds: seconds)
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
