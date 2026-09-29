import FNMNCore
import SwiftUI

/// What a paragraph can do with itself or with text selected in it. The same actions back the
/// paragraph's context menu and the system edit menu, so both always offer the same items.
struct ParagraphActions {
    let materialID: String
    let annotations: [Annotation]
    let perform: (AnnotationCommand, AnnotationTarget) -> Void
    let note: (Int) -> Void
    let ask: (String) -> Void
    let copyPrompt: (String) -> Void

    func target(_ piece: Int, text: String, span: TextSpan? = nil) -> AnnotationTarget {
        AnnotationTarget(materialID: materialID, piece: piece, text: text, span: span)
    }

    func commands(_ target: AnnotationTarget) -> [AnnotationCommand] {
        annotationCommands(annotations, at: target)
    }
}

extension AnnotationCommand {
    var title: String {
        switch self {
        case .mark(.highlight): "Highlight"
        case .unmark(.highlight): "Remove Highlight"
        case .mark(.strikethrough): "Strikethrough"
        case .unmark(.strikethrough): "Remove Strikethrough"
        }
    }

    var systemImage: String {
        switch self {
        case .mark(.highlight), .unmark(.highlight): "highlighter"
        case .mark(.strikethrough), .unmark(.strikethrough): "strikethrough"
        }
    }
}

struct ReadingSession: View {
    @Environment(LibraryModel.self) private var library
    let markdown: String
    let file: (String) -> URL?
    let materialID: String
    let header: MaterialHeader
    let piece: Int?
    var onVisiblePiece: (Int, Int) -> Void = { _, _ in }

    @State private var fold = ReadingFold.open
    @State private var notePiece: Int?
    @State private var noteDraft = ""
    @State private var place: Int?
    @State private var scrollID: Int?
    @State private var holdingPlace = false

    var body: some View {
        let pieces = ArticleBody.pieces(in: markdown)
        let visible = visiblePieceIndexes(in: pieces, fold: fold)
        DocumentColumn(
            pieces: pieces,
            visible: visible,
            file: file,
            header: header,
            marks: { quoteMarks(for: $0) },
            tint: readingPlaceTarget(place: place ?? piece, visible: visible),
            scrollID: $scrollID,
            actions: actions
        )
        .onChange(of: piece, initial: true) { _, piece in
            guard let piece else { return }
            place = piece
            guard scrollID != piece else { return }
            holdingPlace = true
            scrollID = piece
        }
        .onChange(of: scrollID) { _, index in
            guard let index, pieces.indices.contains(index) else { return }
            if holdingPlace {
                holdingPlace = false
                return
            }
            place = index
            onVisiblePiece(index, pieces.count)
        }
        .simultaneousGesture(
            MagnificationGesture().onEnded { scale in
                let next: ReadingFold
                if scale < 1 {
                    next = readingFoldPinchIn(fold, pieces: pieces)
                } else if scale > 1 {
                    next = readingFoldPinchOut(fold, pieces: pieces)
                } else {
                    return
                }
                guard next != fold else { return }
                fold = next
                let shown = visiblePieceIndexes(in: pieces, fold: next)
                guard let target = readingPlaceTarget(place: place ?? piece, visible: shown), scrollID != target else { return }
                holdingPlace = true
                scrollID = target
            }
        )
        .alert("Note", isPresented: Binding(
            get: { notePiece != nil },
            set: { if !$0 { notePiece = nil } }
        )) {
            TextField("Note", text: $noteDraft)
            Button("Save") {
                guard let index = notePiece else { return }
                let text = noteDraft
                notePiece = nil
                Task { await library.apply(.note(text, actions.target(index, text: ""))) }
            }
            Button("Cancel", role: .cancel) { notePiece = nil }
        }
    }

    private var actions: ParagraphActions {
        ParagraphActions(
            materialID: materialID,
            annotations: library.snapshot.annotations.filter { $0.materialID == materialID },
            perform: { command, target in
                let change: LibraryChange = switch command {
                case let .mark(mark): .mark(mark, target)
                case let .unmark(mark): .unmark(mark, target)
                }
                Task { await library.apply(change) }
            },
            note: beginNote,
            ask: { ChatGPTHandoff.copyAndOpen(title: header.title, passage: $0) },
            copyPrompt: { _ = ChatGPTHandoff.remember(title: header.title, passage: $0) }
        )
    }

    private func beginNote(_ index: Int) {
        noteDraft = library.snapshot.annotations
            .first { $0.materialID == materialID && $0.piece == index && $0.quote.isEmpty }?
            .note ?? ""
        notePiece = index
    }

    private func quoteMarks(for index: Int) -> [ParagraphQuoteMark] {
        library.snapshot.annotations
            .filter { $0.materialID == materialID && $0.piece == index }
            .compactMap { annotation in
                guard let mark = annotation.mark, !annotation.quote.isEmpty else { return nil }
                return ParagraphQuoteMark(quote: annotation.quote, mark: mark)
            }
    }
}

func readableText(_ piece: ArticlePiece) -> String? {
    switch piece {
    case let .paragraph(runs):
        if let heading = ArticleBody.heading(runs) {
            return heading.title
        }
        let text = runs.map(ArticleBody.plainRun).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    case let .displayMath(latex):
        return latex
    case .image, .video, .interactive:
        return nil
    }
}
