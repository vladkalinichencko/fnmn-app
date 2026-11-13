import SwiftUI

extension View {
    func appRefresh(title: String) -> some View {
        modifier(AppRefresh(title: title))
    }
}

private struct AppRefresh: ViewModifier {
    @Environment(LibraryModel.self) private var library
    @Environment(DigestModel.self) private var digests
    let title: String

    func body(content: Content) -> some View {
        content
            .refreshable {
                await library.syncWithOtherDevices()
                await digests.sync(folder: library.cloudFolder)
            }
            .toolbarTitleDisplayMode(.automatic)
            .toolbar {
                ToolbarItem(placement: .largeTitle) {
                    HStack(spacing: 10) {
                        Text(title)
                            .font(.largeTitle.weight(.bold))
                            .lineLimit(1)
                        if library.syncState == .syncing || digests.syncState == .syncing {
                            ProgressView()
                                .controlSize(.regular)
                                .progressViewStyle(GraySpinner())
                        } else if case let .waiting(pending) = library.syncState {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.title)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Waiting for \(pending) iCloud files")
                        } else if !digests.pendingDownloads.isEmpty || digests.deliveryFailed {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.title)
                                .foregroundStyle(.orange)
                                .accessibilityLabel(digests.pendingDownloads.isEmpty ? "Digest delivery failed" : "Waiting for \(digests.pendingDownloads.count) digest files in iCloud")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
    }
}
