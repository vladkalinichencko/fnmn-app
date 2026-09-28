import SwiftUI
import Observation

@main
struct FNMNApp: App {
    @State private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            SceneRoot()
                .environment(library)
        }
    }
}

@MainActor @Observable
final class WindowNavigation {
    var openMaterialID: String?
    var pendingShare: URL?
    var ownsPreparation = false

    func open(_ materialID: String) {
        openMaterialID = materialID
    }
}

private struct SceneRoot: View {
    @Environment(LibraryModel.self) private var library
    @State private var navigation = WindowNavigation()
    @State private var pendingContinue = false

    var body: some View {
        AppShell()
            .environment(navigation)
            .task { if library.loadState == .loading { await library.load() } }
            .onOpenURL(perform: handleOpenURL)
            .onChange(of: library.loadState) { _, state in
                guard state == .ready, pendingContinue else { return }
                pendingContinue = false
                openContinued()
            }
    }

    private func handleOpenURL(_ url: URL) {
        if url.scheme == "fnmn", url.host == "continue" {
            if library.loadState == .ready {
                openContinued()
            } else {
                pendingContinue = true
            }
            return
        }
        guard let shared = CaptureHandoff.sharedURL(from: url) else { return }
        navigation.pendingShare = shared
    }

    private func openContinued() {
        guard let id = library.snapshot.continuedID, !library.snapshot.isArchived(id) else { return }
        navigation.open(id)
    }
}
