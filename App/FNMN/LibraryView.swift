import SwiftUI
import UniformTypeIdentifiers

private enum LibraryDestination: String, Identifiable {
    case addArticle
    case importPackage
    case importBook
    case newFolder

    var id: String { rawValue }
}

private struct LibraryViewState {
    var selection: String?
    var destination: LibraryDestination?
}

private enum LibraryAction {
    case select(String?)
    case present(LibraryDestination)
    case dismiss
}

private func reduce(_ state: LibraryViewState, _ action: LibraryAction) -> LibraryViewState {
    var state = state
    switch action {
    case let .select(materialID): state.selection = materialID
    case let .present(destination): state.destination = destination
    case .dismiss: state.destination = nil
    }
    return state
}

struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @State private var state = LibraryViewState()
    @State private var newFolder = ""

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
                    LibraryReadyList(selection: selectionBinding)
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup {
                    Group {
                        Button("Add article", systemImage: "link.badge.plus") { send(.present(.addArticle)) }
                        Button("Import package", systemImage: "doc.badge.plus") { send(.present(.importPackage)) }
                        Button("Import book", systemImage: "book.badge.plus") { send(.present(.importBook)) }
                        Button("New folder", systemImage: "folder.badge.plus") { send(.present(.newFolder)) }
                    }
                    .disabled(library.loadState != .ready)
                }
            }
        } detail: {
            if let package = selectedPackage {
                ReaderView(package: package).id(package.material.id)
            } else if let book = selectedBook {
                BookReaderView(record: book).id(book.id)
            } else {
                ContentUnavailableView("Choose a material", systemImage: "books.vertical")
            }
        }
        .sheet(isPresented: destinationBinding(.addArticle)) { AddArticleView() }
        .alert("New folder", isPresented: destinationBinding(.newFolder)) {
            TextField("Name", text: $newFolder)
            Button("Create") {
                Task { await library.addFolder(newFolder) }
                newFolder = ""
                send(.dismiss)
            }
            Button("Cancel", role: .cancel) { newFolder = "" }
        }
        .fileImporter(isPresented: destinationBinding(.importPackage), allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            Task {
                let access = url.startAccessingSecurityScopedResource()
                defer {
                    if access {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do { try await library.importData(Data(contentsOf: url)) }
                catch { library.operationError = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: destinationBinding(.importBook), allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else { return }
            Task {
                let access = url.startAccessingSecurityScopedResource()
                defer {
                    if access {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do { try await library.importBook(from: url) }
                catch { library.operationError = error.localizedDescription }
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

    var body: some View {
        List(selection: $selection) {
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
                    row(book)
                }
            }
            ForEach(library.snapshot.folders, id: \.self) { folder in
                SwiftUI.Section(folder) {
                    ForEach(library.snapshot.packages(in: folder), id: \.material.id) { package in
                        row(package)
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
    @State private var folder = "Inbox"
    @State private var allowsInsecureLAN = false
    @State private var state = ArticleImportState.editing

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
            .disabled(state.isSubmitting)
            .navigationTitle("Add article")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(state.isSubmitting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { send(.submit) }.disabled(state.isSubmitting || URL(string: articleURL) == nil || URL(string: endpoint) == nil || token.isEmpty)
                }
            }
            .overlay {
                if state.isSubmitting {
                    ProgressView()
                }
            }
        }
        .alert("Import failed", isPresented: .init(
            get: { state.failure != nil },
            set: { if !$0 { send(.dismissFailure) } }
        )) {
            Button("OK") { send(.dismissFailure) }
        } message: {
            Text(state.failure ?? "")
        }
    }

    private func send(_ action: ArticleImportAction) {
        state = reduce(state, action)
        guard case .submit = action else {
            if case .completed = state { dismiss() }
            return
        }
        guard let url = URL(string: articleURL), let server = URL(string: endpoint) else { return }
        let token = token
        let folder = folder.isEmpty ? nil : folder
        let allowsInsecureLAN = allowsInsecureLAN
        Task {
            do {
                try await library.importArticle(
                    url: url,
                    endpoint: server,
                    token: token,
                    folder: folder,
                    allowsInsecureLAN: allowsInsecureLAN
                )
                send(.succeeded)
            } catch {
                send(.failed(error.localizedDescription))
            }
        }
    }
}

private enum ArticleImportState: Equatable {
    case editing
    case submitting
    case failed(String)
    case completed

    var isSubmitting: Bool { self == .submitting }
    var failure: String? {
        guard case let .failed(message) = self else { return nil }
        return message
    }
}

private enum ArticleImportAction {
    case submit
    case succeeded
    case failed(String)
    case dismissFailure
}

private func reduce(_ state: ArticleImportState, _ action: ArticleImportAction) -> ArticleImportState {
    switch (state, action) {
    case (.editing, .submit), (.failed, .submit): .submitting
    case (.submitting, .succeeded): .completed
    case let (.submitting, .failed(message)): .failed(message)
    case (.failed, .dismissFailure): .editing
    default: state
    }
}
