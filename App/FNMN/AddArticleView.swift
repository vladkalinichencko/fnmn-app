import SwiftUI

struct AddArticleView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var articleURL = ""
    @State private var endpoint = "http://127.0.0.1:8765"
    @State private var token = ""
    @State private var allowsInsecureLAN = false
    @State private var pickingDocument = false
    @State private var pickingBookFolder = false
    @State private var pickedFolders = Set<String>()
    @State private var newFolder = ""
    @State private var creatingFolder = false

    init(initialURL: String = "") {
        _articleURL = State(initialValue: initialURL)
    }

    var body: some View {
        NavigationStack {
            Group {
                if case let .working(status) = library.preparation {
                    ProgressView(status)
                        .navigationTitle("Add")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                        }
                } else if case let .choosing(materialID) = library.preparation {
                    Group {
                        if library.snapshot.folders.isEmpty {
                            ContentUnavailableView("No folders", systemImage: "folder", description: Text("Create one, then select it."))
                        } else {
                            List(library.snapshot.folders, id: \.self, selection: $pickedFolders) { name in
                                Text(name)
                            }
                            .environment(\.editMode, .constant(.active))
                        }
                    }
                    .navigationTitle("Folders")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                library.finishPreparation()
                                dismiss()
                            }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button("New folder", systemImage: "plus") { creatingFolder = true }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { confirmFolders(materialID) }
                                .disabled(pickedFolders.isEmpty)
                        }
                    }
                } else {
                    Form {
                        TextField("Article URL", text: $articleURL).textContentType(.URL).keyboardType(.URL)
                        Button("Choose document") { pickingDocument = true }
                        Button("Choose book folder") { pickingBookFolder = true }
                        SwiftUI.Section("Mac service") {
                            TextField("Server URL", text: $endpoint).textContentType(.URL).keyboardType(.URL)
                            SecureField("Bearer token", text: $token)
                            Toggle("Allow HTTP on local network", isOn: $allowsInsecureLAN)
                        }
                    }
                    .navigationTitle("Add")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") { submitLink() }.disabled(URL(string: articleURL) == nil)
                        }
                    }
                }
            }
        }
        .alert("New folder", isPresented: $creatingFolder) {
            TextField("Name", text: $newFolder)
            Button("Create") {
                let name = newFolder
                newFolder = ""
                Task { await library.addFolder(name) }
            }
            .disabled(newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { newFolder = "" }
        }
        .onAppear { library.pendingShare = nil }
        .onChange(of: library.pendingShare) { _, shared in
            guard let shared else { return }
            articleURL = shared.absoluteString
            library.pendingShare = nil
        }
        .alert("Import failed", isPresented: .init(
            get: { if case .failed = library.preparation { true } else { false } },
            set: { if !$0 { library.finishPreparation() } }
        )) {
            Button("OK") { library.finishPreparation() }
        } message: {
            Text(library.preparation.failure ?? "")
        }
        .fileImporter(isPresented: $pickingDocument, allowedContentTypes: [.json, .pdf]) { result in
            guard case let .success(url) = result else { return }
            beginSave(url)
        }
        .fileImporter(isPresented: $pickingBookFolder, allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else { return }
            beginSave(url)
        }
    }

    private func submitLink() {
        guard let url = URL(string: articleURL) else { return }
        guard let source = CaptureRoute.source(for: url) else {
            library.preparation = .failed("Enter an http or https link.")
            return
        }
        switch source {
        case .web, .arxiv, .youtube, .x, .substack, .chatgpt:
            break
        case .pdf:
            library.preparation = .failed(CaptureError.unprepared(source).localizedDescription)
            return
        }
        guard let server = URL(string: endpoint), !token.isEmpty else {
            library.preparation = .failed("The Mac service needs a server URL and token.")
            return
        }
        let token = token
        let allowsInsecureLAN = allowsInsecureLAN
        Task { await library.prepareLink(url: url, endpoint: server, token: token, allowsInsecureLAN: allowsInsecureLAN) }
    }

    private func beginSave(_ url: URL) {
        Task { await library.prepareFile(at: url) }
    }

    private func confirmFolders(_ materialID: String) {
        let names = Array(pickedFolders)
        Task {
            await library.assign(materialID: materialID, to: names)
            if library.operationError == nil {
                library.finishPreparation()
                dismiss()
            }
        }
    }
}

extension Preparation {
    var failure: String? {
        guard case let .failed(message) = self else { return nil }
        return message
    }
}
