import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @State private var selection: String?
    @State private var showingAdd = false
    @State private var showingImporter = false
    @State private var showingNewFolder = false
    @State private var newFolder = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if let continued = continuedPackage {
                    SwiftUI.Section("Continue") { MaterialRow(package: continued).tag(continued.material.id) }
                }
                SwiftUI.Section("Materials") {
                    ForEach(library.snapshot.packages, id: \.material.id) { package in
                        MaterialRow(package: package)
                            .tag(package.material.id)
                            .draggable(package.material.id)
                    }
                }
                ForEach(library.snapshot.folders, id: \.self) { folder in
                    SwiftUI.Section(folder) {
                        ForEach(library.snapshot.packages.filter { $0.folders.contains(folder) }, id: \.material.id) { package in
                            MaterialRow(package: package).tag(package.material.id)
                        }
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        for id in ids {
                            Task { await library.move(materialID: id, to: folder) }
                        }
                        return !ids.isEmpty
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup {
                    Button("Add article", systemImage: "link.badge.plus") { showingAdd = true }
                    Button("Import package", systemImage: "doc.badge.plus") { showingImporter = true }
                    Button("New folder", systemImage: "folder.badge.plus") { showingNewFolder = true }
                }
            }
        } detail: {
            if let package = selectedPackage {
                ReaderView(package: package)
            } else {
                ContentUnavailableView("Choose a material", systemImage: "books.vertical")
            }
        }
        .sheet(isPresented: $showingAdd) { AddArticleView() }
        .alert("New folder", isPresented: $showingNewFolder) {
            TextField("Name", text: $newFolder)
            Button("Create") { Task { await library.addFolder(newFolder); newFolder = "" } }
            Button("Cancel", role: .cancel) { newFolder = "" }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            Task {
                let access = url.startAccessingSecurityScopedResource()
                defer {
                    if access {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do { try await library.importData(Data(contentsOf: url)) }
                catch { library.errorMessage = error.localizedDescription }
            }
        }
        .alert("Import failed", isPresented: .init(get: { library.errorMessage != nil }, set: {
            if !$0 {
                library.errorMessage = nil
            }
        })) {
            Button("OK") { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "") }
    }

    private var selectedPackage: ImportPackage? {
        library.snapshot.packages.first { $0.material.id == selection }
    }

    private var continuedPackage: ImportPackage? {
        library.snapshot.packages.first { library.snapshot.positions[$0.material.id] != nil }
    }
}

private struct MaterialRow: View {
    let package: ImportPackage
    var body: some View {
        Label(package.material.title, systemImage: package.material.kind == .video ? "play.rectangle" : "doc.text")
    }
}

private struct AddArticleView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var articleURL = ""
    @State private var endpoint = "http://127.0.0.1:8765"
    @State private var token = ""
    @State private var folder = "Inbox"
    @State private var allowsInsecureLAN = false
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Article URL", text: $articleURL).textContentType(.URL).keyboardType(.URL)
                SwiftUI.Section("Mac service") {
                    TextField("Server URL", text: $endpoint).textContentType(.URL).keyboardType(.URL)
                    SecureField("Bearer token", text: $token)
                    Toggle("Allow HTTP on local network", isOn: $allowsInsecureLAN)
                }
                TextField("Folder", text: $folder)
            }
            .navigationTitle("Add article")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { submit() }.disabled(submitting || URL(string: articleURL) == nil || URL(string: endpoint) == nil || token.isEmpty)
                }
            }
            .overlay {
                if submitting {
                    ProgressView()
                }
            }
        }
    }

    private func submit() {
        guard let url = URL(string: articleURL), let server = URL(string: endpoint) else { return }
        submitting = true
        Task {
            do {
                try await library.importArticle(
                    url: url,
                    endpoint: server,
                    token: token,
                    folder: folder.isEmpty ? nil : folder,
                    allowsInsecureLAN: allowsInsecureLAN
                )
                dismiss()
            } catch {
                library.errorMessage = error.localizedDescription
                submitting = false
            }
        }
    }
}
