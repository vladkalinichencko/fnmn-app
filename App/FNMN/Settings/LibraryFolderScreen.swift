import SwiftUI
import UniformTypeIdentifiers

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
