import FNMNCore
import SwiftUI

private enum BookText: Equatable {
    case loading
    case ready(String)
    case failed(String)
}

struct BookReaderView: View {
    @Environment(LibraryModel.self) private var library
    let record: BookRecord
    let startPiece: Int?
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
                    file: { library.bookFile(record.directoryName, path: $0) },
                    materialID: record.id,
                    header: MaterialHeader(title: record.metadata.title, source: library.snapshot.source(of: record.id)),
                    startPiece: startPiece ?? savedPiece(in: markdown)
                )
            }
        }
        .task { await open() }
    }

    private func open() async {
        do {
            let markdown = try await library.bookText(record)
            text = .ready(markdown)
        } catch {
            text = .failed(error.localizedDescription)
        }
    }

    private func savedPiece(in markdown: String) -> Int? {
        guard let position = library.snapshot.positions[record.id] else { return nil }
        if let piece = position.pieceIndex { return piece }
        guard let heading = BookCatalog.headingID(in: position) else { return nil }
        let headings = ArticleBody.headings(in: markdown)
        let index = heading - 1
        guard headings.indices.contains(index) else { return nil }
        return headings[index].piece
    }
}
