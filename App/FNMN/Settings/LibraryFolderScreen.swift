import SwiftUI
import UniformTypeIdentifiers

/// The library lives in the FNMN folder in iCloud Drive. Without a paid developer account the app has no
/// iCloud container of its own, so iOS lets it into that folder only after the reader points to it once;
/// the app asks for it before anything else.
struct LibraryFolderScreen: View {
    @Environment(ImportJobs.self) private var imports

    var body: some View {
        ContentUnavailableView {
            Label("Choose the FNMN folder", systemImage: "folder")
        } description: {
            Text("Feynman keeps its library in the FNMN folder in iCloud Drive. iOS lets the app in there once you point to it.")
        } actions: {
            if let job = imports.jobs.first(where: \.readsLibraryFolder) {
                JobStatus(phase: job.phase)
                    .frame(maxWidth: 280)
            }
            ChooseLibraryFolderButton(title: "Choose Folder")
                .buttonStyle(.glassProminent)
        }
    }
}

private extension ImportJob {
    var readsLibraryFolder: Bool {
        if case .libraryFolder = input { true } else { false }
    }
}

/// Picks the library folder and reads it as an import, so its progress shows on a tile and in the Live Activity.
struct ChooseLibraryFolderButton: View {
    let title: LocalizedStringKey
    @Environment(ImportJobs.self) private var imports
    @State private var isPicking = false

    var body: some View {
        Button(title, systemImage: "folder") { isPicking = true }
            .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
                if case let .success(folder) = result {
                    imports.send(.submit(.libraryFolder(folder), id: UUID()))
                }
            }
    }
}
