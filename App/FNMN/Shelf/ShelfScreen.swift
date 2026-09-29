import FNMNCore
import SwiftUI

struct ShelfScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.shelf) {
            List {
                ForEach(library.snapshot.annotationGroups) { group in
                    Section {
                        ForEach(group.annotations) { annotation in
                            AnnotationRow(annotation: annotation)
                        }
                    } header: {
                        Button(group.item.title) { navigation.open(.item(group.item.id)) }
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
                let archived = library.snapshot.archivedItems
                if !archived.isEmpty {
                    Section {
                        ItemGrid(items: archived)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("Archive").font(.title2.bold()).foregroundStyle(.primary).textCase(nil)
                    }
                }
            }
            .overlay {
                if library.snapshot.annotationGroups.isEmpty && library.snapshot.archivedItems.isEmpty {
                    ContentUnavailableView("Nothing on the shelf", systemImage: "bookmark", description: Text("Highlights, notes and archived materials appear here."))
                }
            }
            .navigationTitle("Shelf")
        }
    }
}

private struct AnnotationRow: View {
    let annotation: Annotation
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.open(.item(annotation.materialID, piece: annotation.piece))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if !annotation.quote.isEmpty {
                    Text(annotation.quote)
                        .strikethrough(annotation.mark == .strikethrough)
                        .lineLimit(8)
                }
                if !annotation.note.isEmpty {
                    Text(annotation.note).foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = [annotation.quote, annotation.note].filter { !$0.isEmpty }.joined(separator: "\n\n")
            }
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
    }

    private func delete() {
        Task { await library.apply(.removeAnnotation(annotation.id)) }
    }
}
