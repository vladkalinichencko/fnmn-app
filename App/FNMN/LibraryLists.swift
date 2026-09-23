import SwiftUI

struct LibraryReadyList: View {
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

struct MaterialRow: View {
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

struct FoldersView: View {
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
                        Task { await library.place(materialID: id, in: folder) }
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

struct FolderContents: View {
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
