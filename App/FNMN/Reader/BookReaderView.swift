import FNMNCore
import SwiftUI

private enum BookText {
    case loading
    case ready(ReaderCoordinator)
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
            case let .ready(reader):
                MaterialReader(reader: reader)
            }
        }
        .task { await open() }
    }

    private func open() async {
        do {
            let markdown = try await library.bookText(record)
            let document = await Self.document(markdown, title: record.metadata.title)
            text = .ready(ReaderCoordinator(
                document: document,
                materialID: record.id,
                title: record.metadata.title,
                source: library.snapshot.source(of: record.id),
                baseURL: library.bookFolder(record.directoryName),
                start: startPiece ?? savedPiece(in: document),
                library: library
            ))
        } catch {
            text = .failed(error.localizedDescription)
        }
    }

    @concurrent
    private static func document(_ markdown: String, title: String) async -> ReaderDocument {
        ReaderDocument(markdown: markdown, title: title)
    }

    private func savedPiece(in document: ReaderDocument) -> Int? {
        guard let position = library.position(of: record.id) else { return nil }
        if let piece = position.pieceIndex { return piece }
        guard let heading = BookCatalog.headingID(in: position) else { return nil }
        let headings = document.blocks.indices.filter { if case .heading = document.blocks[$0] { true } else { false } }
        let index = heading - 1
        guard headings.indices.contains(index) else { return nil }
        return headings[index]
    }
}
