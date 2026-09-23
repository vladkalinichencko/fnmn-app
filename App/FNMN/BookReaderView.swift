import SwiftUI

private enum BookText: Equatable {
    case loading
    case ready(String)
    case failed(String)
}

private enum BookLoadAction {
    case loaded(String)
    case failed(String)
}

private func reduce(_ text: BookText, _ action: BookLoadAction) -> BookText {
    switch action {
    case let .loaded(markdown): .ready(markdown)
    case let .failed(message): .failed(message)
    }
}

struct BookReaderView: View {
    @Environment(LibraryModel.self) private var library
    let record: BookRecord
    @State private var text = BookText.loading

    var body: some View {
        Group {
            switch text {
            case .loading:
                ProgressView()
            case let .failed(message):
                ContentUnavailableView("Couldn’t open the book", systemImage: "book.closed", description: Text(message))
            case let .ready(markdown):
                MaterialReader(
                    markdown: markdown,
                    file: { LibraryFile.bookFile(root: library.storageURL, directoryName: record.directoryName, path: $0) },
                    materialID: record.id,
                    title: record.metadata.title,
                    outline: outline(in: markdown),
                    startPiece: startPiece(in: markdown)
                )
            }
        }
        .navigationTitle(record.metadata.title)
        .task { await open() }
    }

    private func open() async {
        let storage = library.storageURL
        let directoryName = record.directoryName
        let contentFile = record.metadata.contentFile
        do {
            let markdown = try await LibraryFile(url: storage).bookText(directoryName: directoryName, contentFile: contentFile)
            text = reduce(text, .loaded(markdown))
        } catch {
            text = reduce(text, .failed(error.localizedDescription))
        }
    }

    private func outline(in markdown: String) -> [OutlineEntry] {
        let ordinals = ArticleBody.headingOrdinals(in: ArticleBody.pieces(in: markdown))
        return record.metadata.toc.compactMap { entry in
            guard let piece = ordinals.firstIndex(where: { $0 == entry.ordinal }) else { return nil }
            return OutlineEntry(piece: piece, level: entry.level, title: entry.title)
        }
    }

    private func startPiece(in markdown: String) -> Int? {
        guard let position = library.snapshot.positions[record.id] else { return nil }
        if let piece = position.pieceIndex { return piece }
        guard let heading = BookCatalog.headingID(in: position) else { return nil }
        return ArticleBody.headingOrdinals(in: ArticleBody.pieces(in: markdown)).firstIndex { $0 == heading }
    }
}
