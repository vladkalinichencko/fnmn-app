import FNMNCore
import SwiftUI

struct ShelfScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ImportJobs.self) private var imports
    @Environment(WindowNavigation.self) private var navigation
    @State private var query = ""

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.shelf) {
            let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let annotations = AnnotationEntry.all(in: library.queries.annotationGroups(matching: query))
                .sorted { ($0.annotation.updatedAt ?? .distantPast) > ($1.annotation.updatedAt ?? .distantPast) }
            let archived = library.queries.search(query, in: library.queries.archivedItems)
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.sectionGap * 1.4) {
                    if !annotations.isEmpty {
                        ShelfSection("Annotations", route: .annotations) {
                            CardColumns(
                                items: annotations,
                                idealWidth: 300,
                                spacing: Tokens.sectionGap,
                                height: { entry, _ in Double(entry.weight) },
                                limit: searching ? nil : { $0 == 1 ? 3 : 2 * $0 }
                            ) { entry in
                                AnnotationCard(entry: entry)
                            }
                        }
                    }
                    if !archived.isEmpty {
                        ShelfSection("Archive", route: .archive) {
                            ItemGrid(items: searching ? archived : Array(archived.prefix(4)))
                        }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, Tokens.sectionGap)
            }
            .background(Tokens.canvas)
            .overlay {
                if !searching, annotations.isEmpty && archived.isEmpty {
                    switch Self.placeholder(settling: settling) {
                    case .loading: Loading()
                    case .empty:
                        ContentUnavailableView("Nothing on the shelf", systemImage: "bookmark", description: Text("Highlights, notes and archived items appear here."))
                    }
                }
            }
            .noResults(for: query, when: annotations.isEmpty && archived.isEmpty)
            .screenSearch($query)
            .navigationTitle("Shelf")
            .appRefresh(title: "Shelf")
        } destination: { route in
            RouteScreen(route: route)
        }
    }

    private var settling: Bool {
        library.syncState == .syncing || imports.jobs.contains { $0.isPreparing }
    }

    enum Placeholder {
        case loading, empty
    }

    static func placeholder(settling: Bool) -> Placeholder {
        settling ? .loading : .empty
    }
}

private struct ShelfSection<Content: View>: View {
    let title: String
    let route: Route
    let content: Content
    @Environment(WindowNavigation.self) private var navigation

    init(_ title: String, route: Route, @ViewBuilder content: () -> Content) {
        self.title = title
        self.route = route
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.gap) {
            Button { navigation.open(route) } label: {
                Text("\(title) \(Text(Image(systemName: "chevron.forward")).font(.title3.weight(.semibold)).foregroundStyle(.secondary).baselineOffset(Self.chevronRise))")
                    .font(Tokens.sectionTitle)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            content
        }
    }

    private static var chevronRise: CGFloat {
        (UIFont.preferredFont(forTextStyle: .title1).capHeight - UIFont.preferredFont(forTextStyle: .title3).capHeight) / 2
    }
}

struct AnnotationsScreen: View {
    @Environment(LibraryModel.self) private var library
    @State private var query = ""

    var body: some View {
        let entries = AnnotationEntry.all(in: library.queries.annotationGroups(matching: query))
        ScrollView {
            CardColumns(items: entries, idealWidth: 300, spacing: Tokens.sectionGap, height: { entry, _ in Double(entry.weight) }) { entry in
                AnnotationCard(entry: entry)
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.gap)
        }
        .background(Tokens.canvas)
        .noResults(for: query, when: entries.isEmpty)
        .screenSearch($query)
        .navigationTitle("Annotations")
    }
}

struct ArchiveScreen: View {
    @Environment(LibraryModel.self) private var library
    @State private var query = ""

    var body: some View {
        let found = library.queries.search(query, in: library.queries.archivedItems)
        ScrollView {
            ItemGrid(items: found, query: query).padding(.horizontal, Tokens.gutter)
        }
        .background(Tokens.canvas)
        .noResults(for: query, when: found.isEmpty)
        .screenSearch($query)
        .navigationTitle("Archive")
    }
}

private struct AnnotationEntry: Identifiable {
    let item: LibraryItem
    let annotation: Annotation
    var id: UUID { annotation.id }

    static func all(in groups: [AnnotationGroup]) -> [AnnotationEntry] {
        groups.flatMap { group in group.annotations.map { AnnotationEntry(item: group.item, annotation: $0) } }
    }

    var weight: Int {
        60 + min(annotation.text.count, 260) + annotation.note.count + item.title.count / 4
    }
}

private struct AnnotationCard: View {
    let entry: AnnotationEntry
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @State private var quoteHeight: CGFloat = 0

    var body: some View {
        let annotation = entry.annotation
        Button {
            navigation.open(.item(annotation.materialID, piece: annotation.piece))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.item.title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                composition
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = [annotation.quoted, annotation.note].filter { !$0.isEmpty }.joined(separator: "\n\n")
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await library.apply(.removeAnnotation(annotation.id)) }
            }
        }
    }

    @ViewBuilder
    private var composition: some View {
        let annotation = entry.annotation, note = entry.annotation.note
        ZStack(alignment: .topTrailing) {
            if !annotation.text.isEmpty {
                quote(annotation)
                    .padding(note.isEmpty ? .horizontal : .trailing, note.isEmpty ? 22 : 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !note.isEmpty {
                self.note(note, alone: annotation.text.isEmpty)
                    .padding(.leading, annotation.text.isEmpty ? 0 : 64)
                    .rotationEffect(.degrees(annotation.text.isEmpty ? 0 : 1), anchor: .topTrailing)
                    .padding(.top, annotation.text.isEmpty ? 0 : quoteHeight / 2)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func quote(_ annotation: Annotation) -> some View {
        Text(Self.marked(annotation))
            .font(.system(.callout, design: .serif))
            .padding(Tokens.tilePadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .rotationEffect(.degrees(Self.quoteTurn))
            .plate(in: TurnedRectangle(cornerRadius: Tokens.plateRadius, degrees: Self.quoteTurn))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { quoteHeight = $0 }
    }

    private static let quoteTurn = -1.5

    private static func marked(_ annotation: Annotation) -> AttributedString {
        let excerpt = annotation.excerpt()
        var text = AttributedString(excerpt.text)
        for run in excerpt.runs {
            guard let range = Range(run.range, in: text) else { continue }
            switch run.mark {
            case .highlight: text[range].backgroundColor = .highlight
            case .strikethrough: text[range].strikethroughStyle = .single
            }
        }
        return text
    }

    private func note(_ text: String, alone: Bool) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(Tokens.tilePadding - 2)
            .background {
                Rectangle()
                    .fill(.thickMaterial)
                    .overlay(Tokens.canvas.opacity(0.85))
                    .mask { RoundedRectangle(cornerRadius: Tokens.plateRadius, style: .continuous).padding(30).blur(radius: 12) }
                    .padding(-24)
            }
            .frame(maxWidth: alone ? .infinity : nil, alignment: .leading)
    }
}
