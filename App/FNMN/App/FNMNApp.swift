import FNMNCore
import QuickLook
import SwiftUI

@main
struct FNMNApp: App {
    @State private var library: LibraryModel
    @State private var server: ServerLink
    @State private var imports: ImportJobs
    @State private var digests: DigestModel

    init() {
        let library = LibraryModel()
        let server = ServerLink()
        _library = State(initialValue: library)
        _server = State(initialValue: server)
        _imports = State(initialValue: ImportJobs(library: library, server: server))
        _digests = State(initialValue: DigestModel(server: server))
        ReaderAppearance.makeSpeedProfiles()
    }

    var body: some Scene {
        WindowGroup {
            WindowRoot()
                .environment(library)
                .environment(server)
                .environment(imports)
                .environment(digests)
        }
    }
}

private struct WindowRoot: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ImportJobs.self) private var imports
    @Environment(DigestModel.self) private var digests
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = WindowNavigation()
    @State private var dialogs = LibraryDialogs()
    @State private var widgetRefresh: Task<Void, Never>?

    var body: some View {
        Group {
            switch library.phase {
            case .loading:
                Loading()
            case let .failed(message):
                ContentUnavailableView {
                    Label("Library unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await library.load() } }
                }
            case .needsFolder:
                LibraryFolderScreen()
            case .ready:
                AppShell()
            }
        }
        .progressViewStyle(GraySpinner())
        .environment(navigation)
        .environment(dialogs)
        .quickLookPreview(Bindable(library).previewedOriginal)
        .task { await library.load() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                Task {
                    await library.saveProgress()
                    await digests.settle()
                }
            case .active where library.phase == .ready:
                takeSharedItems()
                Task {
                    await library.syncWithOtherDevices()
                    await digests.sync(folder: library.cloudFolder)
                }
            default: break
            }
        }
        .onChange(of: library.phase) { _, phase in
            guard phase == .ready else {
                return
            }
            takeSharedItems()
            Task { await digests.sync(folder: library.cloudFolder) }
            navigation.showPending(phase: phase) {
                continuedRoute()
            }
        }
        .onChange(of: library.phase) { _, phase in
            guard phase == .ready, let route = navigation.pendingItem else {
                return
            }
            navigation.pendingItem = nil
            navigation.show(route)
        }
        .task { await WidgetSnapshotBuilder.refresh(library: library, digests: digests) }
        .onChange(of: library.snapshot) { scheduleWidgetRefresh() }
        .onChange(of: library.progress) { scheduleWidgetRefresh() }
        .onChange(of: digests.current?.id) { scheduleWidgetRefresh() }
        .onChange(of: scenePhase) {
            guard scenePhase == .background else {
                return
            }
            Task { await WidgetSnapshotBuilder.refresh(library: library, digests: digests) }
        }
        .onChange(of: library.cloudFolder) { _, folder in
            guard let folder else {
                return
            }
            Task { await digests.sync(folder: folder) }
        }
        .onOpenURL { url in
            if url.scheme == "fnmn", url.host == "continue" {
                navigation.pending = .continueReading
                navigation.showPending(phase: library.phase) {
                    continuedRoute()
                }
            } else if url.scheme == "fnmn", url.host == "digest" {
                navigation.tab = .digest
            } else if url.scheme == "fnmn", url.host == "item",
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
                      !id.isEmpty {
                let piece = components.queryItems?.first { $0.name == "piece" }?.value.flatMap(Int.init)
                if library.phase == .ready {
                    navigation.show(.item(id, piece: piece))
                } else {
                    navigation.pendingItem = .item(id, piece: piece)
                }
            } else if let shared = CaptureHandoff.sharedURL(from: url) {
                dialogs.send(.addLink(shared.absoluteString))
            }
        }
        .alert("Couldn’t save the change", isPresented: Binding(
            get: { library.failure != nil },
            set: { if !$0 { library.failure = nil } }
        )) {
            Button("OK") { library.failure = nil }
        } message: {
            Text(library.failure ?? "")
        }
    }

    private func scheduleWidgetRefresh() {
        widgetRefresh?.cancel()
        widgetRefresh = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }
            await WidgetSnapshotBuilder.refresh(library: library, digests: digests)
        }
    }

    private func takeSharedItems() {
        guard let inbox = CaptureInbox() else { return }
        for entry in inbox.take() {
            switch entry {
            case let .link(url): imports.send(.submit(.link(url), id: UUID()))
            case let .file(url): imports.send(.submit(.file(url), id: UUID()))
            }
        }
    }

    private func continuedRoute() -> Route? {
        guard let id = library.snapshot.continuedID(library.progress) else {
            return nil
        }
        return .item(id)
    }
}
