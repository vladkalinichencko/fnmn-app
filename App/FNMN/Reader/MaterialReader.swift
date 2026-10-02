import FNMNCore
import SwiftUI
import Textual

/// Reads an article or a book as one column of paragraphs and keeps the place on the paragraph at the top.
struct MaterialReader: View {
    @Environment(LibraryModel.self) private var library
    let reader: ReaderCoordinator
    var sourceURL: URL?

    var body: some View {
        ReadingSession(reader: reader)
            .modifier(ReaderAppearanceModifier())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { SectionTitle(heading: reader.passedHeading) }
                ToolbarItem(placement: .primaryAction) { ReaderMenu(reader: reader, page: sourceURL) }
            }
            .onDisappear { Task { await library.saveProgress() } }
    }
}

/// The heading of the section being read, as plain text on the left of the bar, once the heading itself has gone
/// above the screen. The system's push transition brings a new one up from below while the text goes on down, and
/// down from above while it goes back up, pushing the old one out at once.
private struct SectionTitle: View {
    let heading: (index: Int, title: String)?
    /// The heading shown before this one, which says which way the reader went.
    @State private var last: Int?

    var body: some View {
        let forward = (heading?.index ?? -1) >= (last ?? -1)
        ZStack(alignment: .leading) {
            if let heading {
                Text(MarkedMarkdown.plainText(heading.title, baseURL: nil))
                    .font(.headline)
                    .lineLimit(1)
                    .id(heading.index)
                    .transition(.push(from: forward ? .bottom : .top))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(.snappy(duration: 0.3), value: heading?.index)
        .onChange(of: heading?.index) { _, index in last = index }
    }
}
