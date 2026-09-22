import SwiftUI

private enum ShellTab: Hashable {
    case library
    case shelf
    case search
}

struct AppShell: View {
    @Environment(LibraryModel.self) private var library
    @State private var tab = ShellTab.library

    var body: some View {
        TabView(selection: $tab) {
            Tab("Library", systemImage: "books.vertical", value: ShellTab.library) {
                LibraryView()
            }
            Tab("Shelf", systemImage: "tray.full", value: ShellTab.shelf) {
                ShelfView()
            }
            Tab(value: ShellTab.search, role: .search) {
                NavigationStack {
                    SearchView()
                }
            }
        }
        .onChange(of: library.openMaterialID) { _, id in
            guard id != nil else { return }
            tab = .library
        }
    }
}

private struct SearchView: View {
    @Environment(LibraryModel.self) private var library
    @State private var query = ""

    var body: some View {
        let packages = library.snapshot.matchingPackages(query).filter { !library.snapshot.isArchived($0.material.id) }
        let books = library.snapshot.matchingBooks(query).filter { !library.snapshot.isArchived($0.id) }
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Titles, authors, folders, and section headings."))
            } else if packages.isEmpty && books.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(packages, id: \.material.id) { package in
                    Button(package.material.title) { library.open(package.material.id) }
                }
                ForEach(books) { book in
                    Button(book.metadata.title) { library.open(book.id) }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query)
    }
}

private struct ShelfNote: Identifiable {
    let id: String
    let materialID: String
    let caption: String
    let quote: String
}

struct ShelfView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section("Notes") {
                    let entries = shelfNotes
                    if entries.isEmpty {
                        Text("No notes").foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        Button {
                            library.open(entry.materialID)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(entry.caption)
                                if !entry.quote.isEmpty {
                                    Text(entry.quote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                SwiftUI.Section("Highlights") {
                    let marked = library.snapshot.highlights.filter { $0.mark != nil }
                    if marked.isEmpty {
                        Text("No highlights").foregroundStyle(.secondary)
                    }
                    ForEach(marked) { highlight in
                        Button {
                            library.open(highlight.materialID)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(highlight.quote)
                                if !highlight.caption.isEmpty {
                                    Text(highlight.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                SwiftUI.Section("Read") {
                    materialRows(library.snapshot.readings.filter { $0.value.isRead && !library.snapshot.isArchived($0.key) }.map(\.key))
                }
                SwiftUI.Section("Almost read") {
                    materialRows(library.snapshot.readings.filter {
                        let progress = $0.value.progress ?? 0
                        return progress >= 0.9 && !$0.value.isRead && !library.snapshot.isArchived($0.key)
                    }.map(\.key))
                }
                SwiftUI.Section("Archive") {
                    if library.snapshot.archived.isEmpty {
                        Text("Nothing archived").foregroundStyle(.secondary)
                    }
                    ForEach(library.snapshot.archived, id: \.self) { id in
                        Button(title(id)) { library.open(id) }
                            .swipeActions {
                                Button("Unarchive") { Task { await library.setArchived(false, materialID: id) } }
                            }
                    }
                }
            }
            .navigationTitle("Shelf")
        }
    }

    private var shelfNotes: [ShelfNote] {
        let marked = library.snapshot.highlights.filter { !$0.caption.isEmpty }.map { highlight in
            ShelfNote(id: highlight.id.uuidString, materialID: highlight.materialID, caption: highlight.caption, quote: highlight.quote)
        }
        let earlier = library.snapshot.notes.map { note in
            ShelfNote(id: note.id.uuidString, materialID: note.materialID, caption: note.text, quote: "")
        }
        return marked + earlier
    }

    @ViewBuilder
    private func materialRows(_ ids: [String]) -> some View {
        if ids.isEmpty {
            Text("None").foregroundStyle(.secondary)
        }
        ForEach(ids, id: \.self) { id in
            Button(title(id)) { library.open(id) }
        }
    }

    private func title(_ id: String) -> String {
        if let package = library.snapshot.packages.first(where: { $0.material.id == id }) {
            return package.material.title
        }
        if let book = library.snapshot.books.first(where: { $0.id == id }) {
            return book.metadata.title
        }
        return id
    }
}
