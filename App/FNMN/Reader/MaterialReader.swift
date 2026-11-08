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
            .safeAreaInset(edge: .top, spacing: 0) {
                if reader.state.find != nil {
                    FindBar(reader: reader)
                }
            }
            .modifier(ReaderAppearanceModifier())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { SectionTitle(heading: reader.passedHeading) }
                ToolbarItem(placement: .primaryAction) { ReaderMenu(reader: reader, page: sourceURL) }
            }
            .fullScreenCover(isPresented: Binding(
                get: { reader.state.speedStart != nil },
                set: { if !$0 { reader.send(.speedReading(false)) } }
            )) {
                if let start = reader.state.speedStart {
                    SpeedReader(reader: reader, start: start)
                        .environment(library)
                }
            }
            .onDisappear { Task { await library.saveProgress() } }
    }
}

/// The heading of the section being read, as plain text on the left of the bar, once the heading itself has gone
/// above the screen. A new one replaces the old through the system's blur.
private struct SectionTitle: View {
    let heading: (index: Int, title: String)?

    var body: some View {
        ZStack(alignment: .leading) {
            if let heading {
                Text(MarkedMarkdown.plainText(heading.title, baseURL: nil))
                    .font(.headline)
                    .lineLimit(1)
                    .id(heading.index)
                    .transition(.blurReplace)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.35), value: heading?.index)
    }
}
