import SwiftUI

private enum BookReaderDestination: String, Identifiable {
    case outline
    var id: String { rawValue }
}

private struct BookReaderState {
    var heading: Int?
    var destination: BookReaderDestination?
}

private enum BookReaderAction {
    case restore(Int?)
    case open(Int)
    case present(BookReaderDestination)
    case dismiss
}

private func reduce(_ state: BookReaderState, _ action: BookReaderAction) -> BookReaderState {
    var state = state
    switch action {
    case let .restore(heading):
        state.heading = heading
    case let .open(heading):
        state.heading = heading
    case let .present(destination):
        state.destination = destination
    case .dismiss:
        state.destination = nil
    }
    return state
}

struct BookReaderView: View {
    @Environment(LibraryModel.self) private var library
    let record: BookRecord
    @State private var state = BookReaderState()

    var body: some View {
        BookWebView(
            storage: library.storageURL,
            book: record.directoryName,
            contentFile: record.metadata.contentFile,
            assetsDirectory: record.metadata.assetsDirectory,
            heading: state.heading
        )
            .navigationTitle(record.metadata.title)
            .toolbar {
                Button("Sections", systemImage: "list.bullet.indent") { send(.present(.outline)) }
            }
            .sheet(item: destinationBinding) { _ in
                NavigationStack {
                    List(record.metadata.toc) { entry in
                        Button {
                            send(.open(entry.ordinal))
                            send(.dismiss)
                        } label: {
                            Text(entry.title).padding(.leading, CGFloat(max(0, entry.level - 1)) * 12)
                        }
                    }
                    .navigationTitle("Sections")
                }
            }
            .task { restore() }
    }

    private var destinationBinding: Binding<BookReaderDestination?> {
        Binding(
            get: { state.destination },
            set: { destination in
                if let destination { send(.present(destination)) } else { send(.dismiss) }
            }
        )
    }

    private func restore() {
        guard let position = library.snapshot.positions[record.id] else { return }
        send(.restore(BookCatalog.headingID(in: position)))
    }

    private func send(_ action: BookReaderAction) {
        state = reduce(state, action)
        guard case let .open(heading) = action else { return }
        Task { await library.save(position: BookCatalog.position(heading: heading), materialID: record.id) }
    }
}
