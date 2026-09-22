import SwiftUI

@main
struct FNMNApp: App {
    @State private var library = LibraryModel()
    @State private var pendingContinue = false

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(library)
                .task { await library.load() }
                .onOpenURL(perform: handleOpenURL)
                .onChange(of: library.loadState) { _, state in
                    guard state == .ready, pendingContinue else { return }
                    pendingContinue = false
                    openContinued()
                }
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
        library.pendingShare = shared
    }

    private func openContinued() {
        guard let id = library.snapshot.continuedID, !library.snapshot.isArchived(id) else { return }
        library.open(id)
    }
}
