import SwiftUI

struct ReadingSession: View {
    @Environment(LibraryModel.self) private var library
    let markdown: String
    let file: (String) -> URL?
    let materialID: String
    let title: String
    let piece: Int?
    var onVisiblePiece: (Int, Int) -> Void = { _, _ in }

    @State private var fold = ReadingFold.open
    @State private var selection: Set<Int> = []
    @State private var selectionAnchor: Int?
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
            marks: { quoteMarks(for: $0) },
            tint: readingPlaceTarget(place: place ?? piece, visible: visible),
            selection: selection,
            scrollID: $scrollID,
            onSelect: select,
            onTap: { tap($0, pieces: pieces) },
            onNote: { beginNote($0) },
            onQuote: { index, quote in
                Task { await library.annotate(materialID: materialID, piece: index, quote: quote, caption: nil, mark: .highlight) }
            }
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
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        Button("Copy prompt") { copyPrompt(pieces: pieces) }
                        Button("ChatGPT") { openChatGPT(pieces: pieces) }
                        Button("Highlight") { markSelection(.highlight, pieces: pieces) }
                        Button("Strikethrough") { markSelection(.strikethrough, pieces: pieces) }
                        Button("Done") { clearSelection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
        .alert("Note", isPresented: Binding(
            get: { notePiece != nil },
            set: { if !$0 { notePiece = nil } }
        )) {
            TextField("Note", text: $noteDraft)
            Button("Save") {
                guard let piece = notePiece else { return }
                let caption = noteDraft
                let quote = readableText(pieces[piece]) ?? ""
                notePiece = nil
                Task { await library.annotate(materialID: materialID, piece: piece, quote: quote, caption: caption, mark: nil) }
            }
            Button("Cancel", role: .cancel) { notePiece = nil }
        }
    }

    private func select(_ index: Int) {
        selectionAnchor = index
        selection = [index]
    }

    private func tap(_ index: Int, pieces: [ArticlePiece]) {
        guard let anchor = selectionAnchor else { return }
        if selection == [index] {
            clearSelection()
        } else {
            let lower = min(anchor, index)
            let upper = max(anchor, index)
            selection = Set(lower...upper).intersection(visiblePieceIndexes(in: pieces, fold: fold))
        }
    }

    private func beginNote(_ index: Int) {
        noteDraft = library.snapshot.highlights
            .first { $0.materialID == materialID && $0.piece == index }?
            .caption ?? ""
        notePiece = index
    }

    private func quoteMarks(for index: Int) -> [ParagraphQuoteMark] {
        library.snapshot.highlights
            .filter { $0.materialID == materialID && $0.piece == index }
            .compactMap { highlight in
                guard let mark = highlight.mark, !highlight.quote.isEmpty else { return nil }
                return ParagraphQuoteMark(quote: highlight.quote, mark: mark)
            }
    }

    private func clearSelection() {
        selection = []
        selectionAnchor = nil
    }

    private func copyPrompt(pieces: [ArticlePiece]) {
        let passage = selectedPassage(pieces: pieces)
        guard !passage.isEmpty else { return }
        _ = ChatGPTHandoff.remember(title: title, passage: passage)
        clearSelection()
    }

    private func openChatGPT(pieces: [ArticlePiece]) {
        let passage = selectedPassage(pieces: pieces)
        guard !passage.isEmpty else { return }
        ChatGPTHandoff.copyAndOpen(title: title, passage: passage)
        clearSelection()
    }

    private func markSelection(_ mark: TextMark, pieces: [ArticlePiece]) {
        let indexes = selection.sorted()
        clearSelection()
        Task {
            for index in indexes {
                guard let quote = readableText(pieces[index]), !quote.isEmpty else { continue }
                await library.annotate(materialID: materialID, piece: index, quote: quote, caption: nil, mark: mark)
            }
        }
    }

    private func selectedPassage(pieces: [ArticlePiece]) -> String {
        selection.sorted().compactMap { index -> String? in
            guard pieces.indices.contains(index) else { return nil }
            return readableText(pieces[index])
        }.joined(separator: "\n\n")
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
