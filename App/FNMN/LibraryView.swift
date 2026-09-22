import SwiftUI
import UniformTypeIdentifiers

private enum LibraryDestination: String, Identifiable {
    case addArticle
    case newFolder
    case renameFolder

    var id: String { rawValue }
}

private struct LibraryViewState {
    var selection: String?
    var destination: LibraryDestination?
    var query = ""
    var renaming: String?
}

private enum LibraryAction {
    case select(String?)
    case present(LibraryDestination)
    case dismiss
    case search(String)
    case beginRename(String)
}

private func reduce(_ state: LibraryViewState, _ action: LibraryAction) -> LibraryViewState {
    var state = state
    switch action {
    case let .select(materialID): state.selection = materialID
    case let .present(destination): state.destination = destination
    case .dismiss:
        state.destination = nil
        state.renaming = nil
    case let .search(query): state.query = query
    case let .beginRename(name):
        state.renaming = name
        state.destination = .renameFolder
    }
    return state
}

struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @State private var state = LibraryViewState()
    @State private var newFolder = ""
    @State private var renameText = ""

    var body: some View {
        NavigationSplitView {
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
                    LibraryReadyList(selection: selectionBinding, query: state.query) { folder in
                        renameText = folder
                        send(.beginRename(folder))
                    }
                        .searchable(text: queryBinding)
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup {
                    Group {
                        Button("Add", systemImage: "plus") { send(.present(.addArticle)) }
                        Button("New folder", systemImage: "folder.badge.plus") { send(.present(.newFolder)) }
                    }
                    .disabled(library.loadState != .ready)
                }
            }
        } detail: {
            if let package = selectedPackage {
                if package.body?.isEmpty == false {
                    ArticleFlowView(package: package).id(package.material.id)
                } else {
                    ReaderView(package: package).id(package.material.id)
                }
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
        .alert("New folder", isPresented: destinationBinding(.newFolder)) {
            TextField("Name", text: $newFolder)
            Button("Create") {
                let name = newFolder
                newFolder = ""
                send(.dismiss)
                Task { await library.addFolder(name) }
            }
            Button("Cancel", role: .cancel) { newFolder = "" }
        }
        .alert("Rename folder", isPresented: destinationBinding(.renameFolder)) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                let newName = renameText
                renameText = ""
                if let name = state.renaming {
                    Task { await library.renameFolder(from: name, to: newName) }
                }
                send(.dismiss)
            }
            Button("Cancel", role: .cancel) { renameText = "" }
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
    var rename: (String) -> Void

    var body: some View {
        let packages = library.snapshot.matchingPackages(query)
        let books = library.snapshot.matchingBooks(query)
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
                    if let materialID = library.snapshot.continuedID {
                        SwiftUI.Section("Continue") {
                            if let package = library.snapshot.packages.first(where: { $0.material.id == materialID }) {
                                row(package)
                            } else if let book = library.snapshot.books.first(where: { $0.id == materialID }) {
                                row(book)
                            }
                        }
                    }
                    SwiftUI.Section("Materials") {
                        ForEach(library.snapshot.packages, id: \.material.id) { package in
                            row(package).draggable(package.material.id)
                        }
                        ForEach(library.snapshot.books) { book in
                            row(book).draggable(book.id)
                        }
                    }
                    ForEach(library.snapshot.folders, id: \.self) { folder in
                        SwiftUI.Section {
                            let folderPackages = library.snapshot.packages(in: folder)
                            let folderBooks = library.snapshot.books(in: folder)
                            if folderPackages.isEmpty && folderBooks.isEmpty {
                                Text("No materials").foregroundStyle(.secondary)
                            }
                            ForEach(folderPackages, id: \.material.id) { package in
                                row(package)
                            }
                            ForEach(folderBooks) { book in
                                row(book)
                            }
                        } header: {
                            Text(folder).contextMenu {
                                Button("Rename") { rename(folder) }
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
            }
        }
    }

    private func row(_ package: ImportPackage) -> some View {
        MaterialRow(
            title: package.material.title,
            systemImage: package.material.kind == .video ? "play.rectangle" : "doc.text",
            isRead: library.snapshot.readings[package.material.id]?.isRead ?? false
        ) { isRead in
            Task { await library.setRead(isRead, materialID: package.material.id) }
        }
        .tag(package.material.id)
    }

    private func row(_ book: BookRecord) -> some View {
        MaterialRow(
            title: book.metadata.title,
            systemImage: "book",
            isRead: library.snapshot.readings[book.id]?.isRead ?? false
        ) { isRead in
            Task { await library.setRead(isRead, materialID: book.id) }
        }
        .tag(book.id)
    }
}

private struct MaterialRow: View {
    let title: String
    let systemImage: String
    let isRead: Bool
    let setRead: (Bool) -> Void

    var body: some View {
        labeledTitle
            .swipeActions(edge: .leading) {
                Button(isRead ? "Mark unread" : "Mark read") { setRead(!isRead) }
            }
            .contextMenu {
                Button(isRead ? "Mark unread" : "Mark read") { setRead(!isRead) }
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

private struct AddArticleView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var articleURL = ""
    @State private var endpoint = "http://127.0.0.1:8765"
    @State private var token = ""
    @State private var allowsInsecureLAN = false
    @State private var pickingDocument = false
    @State private var pickingBookFolder = false
    @State private var state = ArticleImportState.editing

    init(initialURL: String = "") {
        _articleURL = State(initialValue: initialURL)
    }

    var body: some View {
        NavigationStack {
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
            .disabled(state.isBusy)
            .navigationTitle("Add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(state.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { send(.submit) }.disabled(state.isBusy || URL(string: articleURL) == nil)
                }
            }
            .overlay {
                if let activity = state.activity {
                    ProgressView(activity)
                }
            }
        }
        .onAppear { library.pendingShare = nil }
        .onChange(of: library.pendingShare) { _, shared in
            guard let shared else { return }
            articleURL = shared.absoluteString
            library.pendingShare = nil
        }
        .alert("Import failed", isPresented: .init(
            get: { state.failure != nil },
            set: { if !$0 { send(.dismissFailure) } }
        )) {
            Button("OK") { send(.dismissFailure) }
        } message: {
            Text(state.failure ?? "")
        }
        .fileImporter(isPresented: $pickingDocument, allowedContentTypes: [.json, .pdf]) { result in
            guard case let .success(url) = result else { return }
            state = reduce(state, .saveLocal)
            Task { await importDocument(url) }
        }
        .fileImporter(isPresented: $pickingBookFolder, allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else { return }
            state = reduce(state, .saveLocal)
            Task { await importDocument(url) }
        }
    }

    private func send(_ action: ArticleImportAction) {
        if case .submit = action {
            submitLink()
            return
        }
        state = reduce(state, action)
        if case .completed = state { dismiss() }
    }

    private func submitLink() {
        guard let url = URL(string: articleURL) else { return }
        state = reduce(state, .submit)
        guard let source = CaptureRoute.source(for: url) else {
            state = reduce(state, .failed("Enter an http or https link."))
            return
        }
        if source != .web {
            state = reduce(state, .failed(CaptureError.unprepared(source).localizedDescription))
            return
        }
        guard let server = URL(string: endpoint), !token.isEmpty else {
            state = reduce(state, .failed("The Mac service needs a server URL and token."))
            return
        }
        let token = token
        let allowsInsecureLAN = allowsInsecureLAN
        Task {
            do {
                let (package, files) = try await ArticleClient(
                    endpoint: server,
                    token: token,
                    allowsInsecureLAN: allowsInsecureLAN
                ).prepare(url: url, folder: CaptureSource.web.folderName)
                send(.pageFetched)
                try await library.storeArticle(package, files: files)
                send(.succeeded)
            } catch {
                send(.failed(error.localizedDescription))
            }
        }
    }

    private func importDocument(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
        }
        do {
            try await library.importPickedDocument(from: url)
            send(.succeeded)
        } catch {
            send(.failed(error.localizedDescription))
        }
    }
}

private enum ArticleImportState: Equatable {
    case editing
    case fetchingPage
    case saving
    case failed(String)
    case completed

    var isBusy: Bool {
        switch self {
        case .fetchingPage, .saving: true
        default: false
        }
    }

    var activity: String? {
        switch self {
        case .fetchingPage: "Fetching the page"
        case .saving: "Saving"
        default: nil
        }
    }

    var failure: String? {
        guard case let .failed(message) = self else { return nil }
        return message
    }
}

private enum ArticleImportAction {
    case submit
    case saveLocal
    case pageFetched
    case succeeded
    case failed(String)
    case dismissFailure
}

private func reduce(_ state: ArticleImportState, _ action: ArticleImportAction) -> ArticleImportState {
    switch (state, action) {
    case (.editing, .submit), (.failed, .submit): .fetchingPage
    case (.editing, .saveLocal), (.failed, .saveLocal): .saving
    case (.fetchingPage, .pageFetched): .saving
    case (.saving, .succeeded): .completed
    case let (.fetchingPage, .failed(message)), let (.saving, .failed(message)): .failed(message)
    case (.failed, .dismissFailure): .editing
    default: state
    }
}
