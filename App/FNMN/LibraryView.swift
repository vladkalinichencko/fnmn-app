import SwiftUI

struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @State private var selection: String?
    @State private var showingAdd = false
    @State private var showingMacConnection = false
    @State private var query = ""

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
                        LibraryReadyList(selection: selectionBinding, query: query)
                    }
                }
                .navigationTitle("Library")
                .searchable(text: $query)
                .toolbar {
                    ToolbarItemGroup {
                        Button("Add", systemImage: "plus") { showingAdd = true }
                            .disabled(library.loadState != .ready)
                        Button("Mac connection", systemImage: "desktopcomputer") { showingMacConnection = true }
                    }
                }
            }
        } detail: {
            if let package = selectedPackage {
                if package.material.kind == .video {
                    VideoReaderView(package: package).id(package.material.id)
                } else {
                    ArticleFlowView(package: package).id(package.material.id)
                }
            } else if let book = selectedBook {
                BookReaderView(record: book).id(book.id)
            } else {
                ContentUnavailableView("Choose a material", systemImage: "books.vertical")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddArticleView(initialURL: navigation.pendingShare?.absoluteString ?? "")
        }
        .sheet(isPresented: $showingMacConnection) {
            MacConnectionView()
        }
        .onChange(of: navigation.pendingShare) { _, shared in
            guard shared != nil, library.loadState == .ready else { return }
            showingAdd = true
        }
        .onChange(of: library.loadState) { _, loadState in
            guard loadState == .ready, navigation.pendingShare != nil else { return }
            showingAdd = true
        }
        .onChange(of: navigation.openMaterialID) { _, id in
            guard let id else { return }
            selection = id
            navigation.openMaterialID = nil
            Task { await library.recordOpening(materialID: id) }
        }
        .onChange(of: library.preparation) { _, phase in
            if case .choosing = phase, navigation.ownsPreparation, !showingAdd {
                showingAdd = true
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
        library.snapshot.packages.first { $0.material.id == selection }
    }

    private var selectedBook: BookRecord? {
        library.snapshot.books.first { $0.id == selection }
    }

    private var selectionBinding: Binding<String?> {
        Binding(get: { selection }, set: { materialID in
            selection = materialID
            if let materialID {
                Task { await library.recordOpening(materialID: materialID) }
            }
        })
    }
}
