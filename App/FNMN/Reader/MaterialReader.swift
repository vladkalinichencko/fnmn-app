import FNMNCore
import SwiftUI

/// Reads an article or a book as one column of paragraphs and keeps the place on the paragraph at the top.
struct MaterialReader: View {
    @Environment(LibraryModel.self) private var library
    let reader: ReaderCoordinator
    var sourceURL: URL?

    var body: some View {
        ReadingSession(reader: reader)
            .modifier(ReaderAppearanceModifier())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ReaderMenu(sourceURL: sourceURL) }
            .task { reader.send(.restore) }
            .onDisappear { Task { await library.saveProgress() } }
    }
}
