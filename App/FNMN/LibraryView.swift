import SwiftUI
import UniformTypeIdentifiers

private enum LibraryDestination: String, Identifiable {
    case addArticle

    var id: String { rawValue }
}

private struct LibraryViewState {
    var selection: String?
    var destination: LibraryDestination?
    var query = ""
}

private enum LibraryAction {
    case select(String?)
    case present(LibraryDestination)
    case dismiss
    case search(String)
}

private func reduce(_ state: LibraryViewState, _ action: LibraryAction) -> LibraryViewState {
    var state = state
    switch action {
    case let .select(materialID): state.selection = materialID
    case let .present(destination): state.destination = destination
    case .dismiss: state.destination = nil
    case let .search(query): state.query = query
    }
    return state
}

struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @State private var state = LibraryViewState()

    var body: some View {
        NavigationSplitView {
            NavigationStack {
            Group {
                switch library.loadState {
                case .loading:
                    ProgressView("Loading library…")
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Library unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { Task { await library.load() } }
                    }
                case .ready:
                    LibraryReadyList(selection: selectionBinding, query: state.query)
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup {
                    Group {
                        Button("Add", systemImage: "plus") { send(.present(.addArticle)) }
                    }
                    .disabled(library.loadState != .ready)
                }
            }
            }
        } detail: {
            if let package = selectedPackage {
                ArticleFlowView(package: package).id(package.material.id)
            } else if let book = selectedBook {
                BookReaderView(record: book).id(book.id)
            } else {
                ContentUnavailableView("Choose a material", systemImage: "books.vertical")
            }
        }
        .sheet(isPresented: destinationBinding(.addArticle)) {
            AddArticleView(initialURL: library.pendingShare?.absoluteString ?? "")
        }
        .onChange(of: library.pendingShare) { _, shared in
            guard shared != nil, library.loadState == .ready else { return }
            send(.present(.addArticle))
        }
        .onChange(of: library.loadState) { _, loadState in
            guard loadState == .ready, library.pendingShare != nil else { return }
            send(.present(.addArticle))
        }
        .onChange(of: library.openMaterialID) { _, id in
            guard let id else { return }
            send(.select(id))
            library.openMaterialID = nil
            Task { await library.recordOpening(materialID: id) }
        }
        .onChange(of: library.preparation) { _, phase in
            if case .choosing = phase, state.destination != .addArticle {
                send(.present(.addArticle))
            }
        }
        .alert("Couldn’t save changes", isPresented: .init(get: { library.operationError != nil }, set: {
            if !$0 {
                library.operationError = nil
            }
        })) {
            Button("OK") { library.operationError = nil }
        } message: { Text(library.operationError ?? "") }
    }

    private var selectedPackage: ImportPackage? {
        library.snapshot.packages.first { $0.material.id == state.selection }
    }

    private var selectedBook: BookRecord? {
        library.snapshot.books.first { $0.id == state.selection }
    }

    private var selectionBinding: Binding<String?> {
        Binding(get: { state.selection }, set: { materialID in
            send(.select(materialID))
            if let materialID {
                Task { await library.recordOpening(materialID: materialID) }
            }
        })
    }

    private var queryBinding: Binding<String> {
        Binding(get: { state.query }, set: { send(.search($0)) })
    }

    private func destinationBinding(_ destination: LibraryDestination) -> Binding<Bool> {
        Binding(
            get: { state.destination == destination },
            set: { isPresented in send(isPresented ? .present(destination) : .dismiss) }
        )
    }

    private func send(_ action: LibraryAction) {
        state = reduce(state, action)
    }
}

private struct LibraryReadyList: View {
    @Environment(LibraryModel.self) private var library
    @Binding var selection: String?
    var query: String

    var body: some View {
        let packages = library.snapshot.matchingPackages(query).filter { !library.snapshot.isArchived($0.material.id) }
        let books = library.snapshot.matchingBooks(query).filter { !library.snapshot.isArchived($0.id) }
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if searching && packages.isEmpty && books.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(selection: $selection) {
                if searching {
                    SwiftUI.Section("Results") {
                        ForEach(packages, id: \.material.id) { package in
                            row(package)
                        }
                        ForEach(books) { book in
                            row(book)
                        }
                    }
                } else {
                    if let materialID = library.snapshot.continuedID, !library.snapshot.isArchived(materialID) {
                        SwiftUI.Section("Continue") {
                            if let package = library.snapshot.packages.first(where: { $0.material.id == materialID }) {
                                row(package)
                            } else if let book = library.snapshot.books.first(where: { $0.id == materialID }) {
                                row(book)
                            }
                        }
                    }
                    SwiftUI.Section("Library") {
                        NavigationLink("Folders") { FoldersView(selection: $selection) }
                    }
                    SwiftUI.Section("Materials") {
                        ForEach(library.snapshot.packages.filter { !library.snapshot.isArchived($0.material.id) }, id: \.material.id) { package in
                            row(package).draggable(package.material.id)
                        }
                        ForEach(library.snapshot.books.filter { !library.snapshot.isArchived($0.id) }) { book in
                            row(book).draggable(book.id)
                        }
                    }
                }
            }
        }
    }

    private func row(_ package: ImportPackage) -> some View {
        MaterialRow(
            title: package.material.title,
            systemImage: package.material.kind == .video ? "play.rectangle" : "doc.text",
            isRead: library.snapshot.readings[package.material.id]?.isRead ?? false,
            progress: library.snapshot.readings[package.material.id]?.progress
        ) { isRead in
            Task { await library.setRead(isRead, materialID: package.material.id) }
        } archive: {
            Task { await library.setArchived(true, materialID: package.material.id) }
        }
        .tag(package.material.id)
    }

    private func row(_ book: BookRecord) -> some View {
        MaterialRow(
            title: book.metadata.title,
            systemImage: "book",
            isRead: library.snapshot.readings[book.id]?.isRead ?? false,
            progress: library.snapshot.readings[book.id]?.progress
        ) { isRead in
            Task { await library.setRead(isRead, materialID: book.id) }
        } archive: {
            Task { await library.setArchived(true, materialID: book.id) }
        }
        .tag(book.id)
    }
}

private struct MaterialRow: View {
    let title: String
    let systemImage: String
    let isRead: Bool
    var progress: Double?
    let setRead: (Bool) -> Void
    let archive: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            labeledTitle
            if let progress {
                ProgressView(value: progress)
            }
        }
        .swipeActions(edge: .leading) {
            Button(isRead ? "Mark unread" : "Mark read") { setRead(!isRead) }
        }
        .contextMenu {
            Button(isRead ? "Mark unread" : "Mark read") { setRead(!isRead) }
            Button("Archive") { archive() }
        }
    }

    @ViewBuilder
    private var labeledTitle: some View {
        let label = Label(title, systemImage: systemImage)
        if isRead {
            label
        } else {
            label.badge("Unread")
        }
    }
}

private struct FoldersView: View {
    @Environment(LibraryModel.self) private var library
    @Binding var selection: String?
    @State private var newFolder = ""
    @State private var creating = false
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(library.snapshot.folders, id: \.self) { folder in
                NavigationLink(folder) {
                    FolderContents(folder: folder, selection: $selection)
                }
                .contextMenu {
                    Button("Rename") {
                        renameText = folder
                        renaming = folder
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
        .navigationTitle("Folders")
        .toolbar {
            Button("New folder", systemImage: "plus") { creating = true }
        }
        .alert("New folder", isPresented: $creating) {
            TextField("Name", text: $newFolder)
            Button("Create") {
                let name = newFolder
                newFolder = ""
                Task { await library.addFolder(name) }
            }
            .disabled(newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { newFolder = "" }
        }
        .alert("Rename folder", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                let newName = renameText
                renameText = ""
                if let name = renaming {
                    Task { await library.renameFolder(from: name, to: newName) }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renameText = "" }
        }
    }
}

private struct FolderContents: View {
    @Environment(LibraryModel.self) private var library
    let folder: String
    @Binding var selection: String?

    var body: some View {
        List {
            let packages = library.snapshot.packages(in: folder)
            let books = library.snapshot.books(in: folder)
            if packages.isEmpty && books.isEmpty {
                ContentUnavailableView("No materials", systemImage: "folder")
            }
            ForEach(packages, id: \.material.id) { package in
                Button { selection = package.material.id } label: {
                    Label(package.material.title, systemImage: package.material.kind == .video ? "play.rectangle" : "doc.text")
                }
            }
            ForEach(books) { book in
                Button { selection = book.id } label: {
                    Label(book.metadata.title, systemImage: "book")
                }
            }
        }
        .navigationTitle(folder)
    }
}

private struct AddArticleView: View {
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
        if source != .web {
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
