import FNMNCore
import SwiftUI

@main
struct FNMNApp: App {
    @State private var library: LibraryModel
    @State private var mac: MacLink
    @State private var imports: ImportJobs

    init() {
        let library = LibraryModel()
        let mac = MacLink()
        _library = State(initialValue: library)
        _mac = State(initialValue: mac)
        _imports = State(initialValue: ImportJobs(library: library, mac: mac))
    }

    var body: some Scene {
        WindowGroup {
            WindowRoot()
                .environment(library)
                .environment(mac)
                .environment(imports)
        }
    }
}

/// One window: its own tab, navigation and dialogs over the shared library.
private struct WindowRoot: View {
    @Environment(LibraryModel.self) private var library
    @State private var navigation = WindowNavigation()
    @State private var dialogs = LibraryDialogs()
    @State private var pendingContinue = false

    var body: some View {
        Group {
            switch library.loadState {
            case .idle, .loading:
                ProgressView()
            case let .failed(message):
                ContentUnavailableView {
                    Label("Library unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await library.load() } }
                }
            case .ready:
                AppShell()
            }
        }
        .environment(navigation)
        .environment(dialogs)
        .task { await library.load() }
        .onChange(of: library.loadState) { _, state in
            guard state == .ready, pendingContinue else { return }
            pendingContinue = false
            continueReading()
        }
        .onOpenURL { url in
            if url.scheme == "fnmn", url.host == "continue" {
                if library.loadState == .ready { continueReading() } else { pendingContinue = true }
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

    private func continueReading() {
        guard let id = library.snapshot.continuedID else { return }
        navigation.show(.item(id))
    }
}
