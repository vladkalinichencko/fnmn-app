import SwiftUI

struct AddArticleView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var articleURL = ""
    @State private var showingMacConnection = false
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
                if case let .working(step) = library.preparation {
                    Group {
                        if let fraction = step.fraction {
                            ProgressView(step.text, value: fraction)
                        } else {
                            ProgressView(step.text)
                        }
                    }
                    .padding()
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
                                navigation.ownsPreparation = false
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
                        Button("Choose library or book folder") { pickingBookFolder = true }
                        SwiftUI.Section("Mac service") {
                            Button {
                                showingMacConnection = true
                            } label: {
                                Label(library.macConnection == nil ? "Set up Mac connection" : "Mac connection", systemImage: "desktopcomputer")
                            }
                        }
                    }
                    .navigationTitle("Add")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                navigation.ownsPreparation = false
                                dismiss()
                            }
                        }
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
        .onAppear { navigation.pendingShare = nil }
        .onChange(of: navigation.pendingShare) { _, shared in
            guard let shared else { return }
            articleURL = shared.absoluteString
            navigation.pendingShare = nil
        }
        .alert("Import failed", isPresented: .init(
            get: { if case .failed = library.preparation { true } else { false } },
            set: {
                if !$0 {
                    library.finishPreparation()
                    navigation.ownsPreparation = false
                }
            }
        )) {
            Button("OK") {
                library.finishPreparation()
                navigation.ownsPreparation = false
            }
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
        .sheet(isPresented: $showingMacConnection) {
            MacConnectionView()
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
        guard library.macConnection != nil else {
            showingMacConnection = true
            return
        }
        navigation.ownsPreparation = true
        Task { await library.prepareLink(url: url) }
    }

    private func beginSave(_ url: URL) {
        navigation.ownsPreparation = true
        Task { await library.prepareFile(at: url) }
    }

    private func confirmFolders(_ materialID: String) {
        let names = Array(pickedFolders)
        Task {
            await library.assign(materialID: materialID, to: names)
            if library.operationError == nil {
                library.finishPreparation()
                navigation.ownsPreparation = false
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
