import FNMNCore
import SwiftUI

/// Highlights and notes, then the archive. Each section shows its latest few; its title opens all of them.
struct ShelfScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.shelf) {
            let annotations = library.snapshot.annotationGroups.flatMap { group in group.annotations.map { (group.item, $0) } }
                .sorted { ($0.1.updatedAt ?? .distantPast) > ($1.1.updatedAt ?? .distantPast) }
            let archived = library.snapshot.archivedItems
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.sectionGap * 1.4) {
                    if !annotations.isEmpty {
                        ShelfSection("Annotations", count: annotations.count, route: .annotations, preview: 3) {
                            VStack(spacing: Tokens.sectionGap) {
                                ForEach(annotations.prefix(3), id: \.1.id) { item, annotation in
                                    AnnotationCard(item: item, annotation: annotation)
                                }
                            }
                        }
                    }
                    if !archived.isEmpty {
                        ShelfSection("Archive", count: archived.count, route: .archive, preview: 4) {
                            ItemGrid(items: Array(archived.prefix(4)))
                        }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, Tokens.sectionGap)
            }
            .background(Tokens.canvas)
            .overlay {
                if annotations.isEmpty && archived.isEmpty {
                    ContentUnavailableView("Nothing on the shelf", systemImage: "bookmark", description: Text("Highlights, notes and archived materials appear here."))
                }
            }
            .navigationTitle("Shelf")
        }
    }
}

/// A large section title; when there is more than the preview holds, it leads to the full list.
private struct ShelfSection<Content: View>: View {
    let title: String
    let count: Int
    let route: Route
    let preview: Int
    @ViewBuilder let content: () -> Content
    @Environment(WindowNavigation.self) private var navigation

    init(_ title: String, count: Int, route: Route, preview: Int, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.count = count
        self.route = route
        self.preview = preview
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.gap) {
            Button { navigation.open(route) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(.largeTitle.weight(.black)).foregroundStyle(.primary)
                    if count > preview {
                        Image(systemName: "chevron.forward").font(.title2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(count <= preview)
            content()
        }
    }
}

/// Every highlight and note, grouped by the material they were made in, newest first.
struct AnnotationsScreen: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.sectionGap) {
                ForEach(library.snapshot.annotationGroups) { group in
                    ForEach(group.annotations) { annotation in
                        AnnotationCard(item: group.item, annotation: annotation)
                    }
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.gap)
        }
        .background(Tokens.canvas)
        .navigationTitle("Annotations")
    }
}

struct ArchiveScreen: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        ScrollView {
            ItemGrid(items: library.snapshot.archivedItems).padding(.horizontal, Tokens.gutter)
        }
        .background(Tokens.canvas)
        .navigationTitle("Archive")
    }
}

/// A quote on a plate turned slightly left, and its note on blurred glass laid over its lower right corner.
private struct AnnotationCard: View {
    let item: LibraryItem
    let annotation: Annotation
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.open(.item(annotation.materialID, piece: annotation.piece))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                composition
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = [annotation.quote, annotation.note].filter { !$0.isEmpty }.joined(separator: "\n\n")
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await library.apply(.removeAnnotation(annotation.id)) }
            }
        }
    }

    @ViewBuilder
    private var composition: some View {
        VStack(alignment: .trailing, spacing: -18) {
            if !annotation.quote.isEmpty {
                quote
                    .padding(.trailing, 44)
                    .rotationEffect(.degrees(-1.5), anchor: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !annotation.note.isEmpty {
                note
                    .padding(.leading, annotation.quote.isEmpty ? 0 : 64)
                    .rotationEffect(.degrees(annotation.quote.isEmpty ? 0 : 1), anchor: .topTrailing)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var quote: some View {
        Text(Self.excerpt(annotation.quote))
            .font(.system(.callout, design: .serif))
            .strikethrough(annotation.mark == .strikethrough)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Tokens.tilePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .plate(cornerRadius: Tokens.plateRadius)
    }

    /// A long quote is cut at a word near 260 characters; a line limit would leave empty space under the text.
    private static func excerpt(_ quote: String) -> String {
        let text = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 260 else { return text }
        let cut = text.prefix(260)
        return String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)]) + "…"
    }

    private var note: some View {
        Text(annotation.note)
            .font(.callout.weight(.medium))
            .padding(Tokens.tilePadding - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: Tokens.plateRadius - 6, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}
