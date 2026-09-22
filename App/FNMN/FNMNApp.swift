import SwiftUI

@main
struct FNMNApp: App {
    @State private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(library)
                .task { await library.load() }
                .onOpenURL { url in
                    guard let shared = CaptureHandoff.sharedURL(from: url) else { return }
                    library.pendingShare = shared
                }
        }
    }
}
