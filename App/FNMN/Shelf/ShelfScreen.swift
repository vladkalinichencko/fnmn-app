import FNMNCore
import SwiftUI

/// Highlights and notes, then the archive. Each section shows its latest few; its title opens all of them.
struct ShelfScreen: View {
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        RouteStack(path: $navigation.shelf) {
            let annotations = library.snapshot.annotationGroups.flatMap { group in group.annotations.map { AnnotationEntry(item: group.item, annotation: $0) } }
                .sorted { ($0.annotation.updatedAt ?? .distantPast) > ($1.annotation.updatedAt ?? .distantPast) }
            let archived = library.snapshot.archivedItems
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.sectionGap * 1.4) {
                    if !annotations.isEmpty {
                        ShelfSection("Annotations", route: .annotations) {
                            AnnotationColumns(entries: annotations, preview: true)
                        }
                    }
                    if !archived.isEmpty {
                        ShelfSection("Archive", route: .archive) {
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

/// A large section title that leads to the full list.
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
            // A symbol inside text is centered on the capitals of its own font. The chevron's font is smaller than the
            // title's, so it is raised by half the difference of their capital heights to sit on the title's middle.
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

/// Every highlight and note, grouped by the material they were made in, newest first.
struct AnnotationsScreen: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        ScrollView {
            AnnotationColumns(entries: library.snapshot.annotationGroups.flatMap { group in
                group.annotations.map { AnnotationEntry(item: group.item, annotation: $0) }
            })
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

private struct AnnotationEntry: Identifiable {
    let item: LibraryItem
    let annotation: Annotation
    var id: UUID { annotation.id }

    /// How much room the card takes, judged by its text, so the columns come out about equally tall.
    var weight: Int {
        60 + min(annotation.quote.count, 260) + annotation.note.count + item.title.count / 4
    }
}

/// Annotation cards in as many columns as the width holds. Each card goes under the column that is shortest so
/// far, so the newest lie along the top; a phone has one column.
private struct AnnotationColumns: View {
    let entries: [AnnotationEntry]
    /// The shelf's preview shows two rows, or three in a single column, instead of every card.
    var preview = false
    /// Until the width is known the cards stay unseen, so a wide screen never shows one column for a frame.
    @State private var width: CGFloat = 0

    var body: some View {
        let count = Tokens.annotationColumns(forWidth: width)
        let shown = preview ? Array(entries.prefix(count == 1 ? 3 : 2 * count)) : entries
        HStack(alignment: .top, spacing: Tokens.sectionGap) {
            ForEach(Array(Self.split(shown, into: count).enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: Tokens.sectionGap) {
                    ForEach(column) { AnnotationCard(item: $0.item, annotation: $0.annotation) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .opacity(width > 0 ? 1 : 0)
    }

    private static func split(_ entries: [AnnotationEntry], into count: Int) -> [[AnnotationEntry]] {
        var columns = Array(repeating: [AnnotationEntry](), count: count)
        var heights = Array(repeating: 0, count: count)
        for entry in entries {
            let shortest = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[shortest].append(entry)
            heights[shortest] += entry.weight
        }
        return columns
    }
}

/// A quote on a plate turned slightly left, and its note on blurred glass laid over its lower right corner.
private struct AnnotationCard: View {
    let item: LibraryItem
    let annotation: Annotation
    @Environment(LibraryModel.self) private var library
    @Environment(WindowNavigation.self) private var navigation
    @State private var quoteHeight: CGFloat = 0

    var body: some View {
        Button {
            navigation.open(.item(annotation.materialID, piece: annotation.piece))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                composition
            }
        }
        .buttonStyle(.plain)
        // Lifted by the frame, the card would show the menu's own plate behind the quote and the note.
        .contentShape(.contextMenuPreview, .rect(cornerRadius: Tokens.plateRadius, style: .continuous))
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = [annotation.quote, annotation.note].filter { !$0.isEmpty }.joined(separator: "\n\n")
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await library.apply(.removeAnnotation(annotation.id)) }
            }
        }
    }

    /// The note starts halfway down the quote's plate. The card is as tall as whichever reaches lower, the quote
    /// or the note, so a short note never lets the quote run into the next card.
    @ViewBuilder
    private var composition: some View {
        ZStack(alignment: .topTrailing) {
            if !annotation.quote.isEmpty {
                // Alone, the quote stands in the middle; with a note, it moves left to make room for it.
                quote
                    .padding(annotation.note.isEmpty ? .horizontal : .trailing, annotation.note.isEmpty ? 22 : 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !annotation.note.isEmpty {
                note
                    .padding(.leading, annotation.quote.isEmpty ? 0 : 64)
                    .rotationEffect(.degrees(annotation.quote.isEmpty ? 0 : 1), anchor: .topTrailing)
                    .padding(.top, annotation.quote.isEmpty ? 0 : quoteHeight / 2)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var quote: some View {
        Text(Self.excerpt(annotation.quote))
            .font(.system(.callout, design: .serif))
            .strikethrough(annotation.mark == .strikethrough)
            .padding(Tokens.tilePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rotationEffect(.degrees(Self.quoteTurn))
            .plate(in: TurnedRectangle(cornerRadius: Tokens.plateRadius, degrees: Self.quoteTurn))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { quoteHeight = $0 }
    }

    private static let quoteTurn = -1.5

    /// A long quote is cut at a word near 260 characters; a line limit would leave empty space under the text.
    private static func excerpt(_ quote: String) -> String {
        let text = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 260 else { return text }
        let cut = text.prefix(260)
        return String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)]) + "…"
    }

    /// The note has no frame: a blur toned to the page color keeps it readable over the quote and disappears into
    /// the page beside it. The blur is drawn well past the text, so its soft edge has faded out completely before
    /// the drawing ends and no rectangle shows.
    private var note: some View {
        Text(annotation.note)
            .font(.callout.weight(.semibold))
            .padding(Tokens.tilePadding - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Rectangle()
                    .fill(.thickMaterial)
                    .overlay(Tokens.canvas.opacity(0.85))
                    .mask { RoundedRectangle(cornerRadius: Tokens.plateRadius, style: .continuous).padding(30).blur(radius: 12) }
                    .padding(-24)
            }
    }
}
