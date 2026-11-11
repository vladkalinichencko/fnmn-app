import SwiftUI

extension View {
    func appRefresh() -> some View {
        modifier(AppRefresh())
    }
}

private struct AppRefresh: ViewModifier {
    @Environment(LibraryModel.self) private var library
    @Environment(DigestModel.self) private var digests

    func body(content: Content) -> some View {
        content
            .refreshable {
                await library.syncWithOtherDevices()
                await digests.sync(folder: library.cloudFolder)
            }
            .toolbar {
                if library.syncState == .syncing || digests.syncState == .syncing {
                    ToolbarItem(placement: .largeTitle) {
                        ProgressView()
                            .controlSize(.small)
                            .progressViewStyle(GraySpinner())
                    }
                }
            }
    }
}
