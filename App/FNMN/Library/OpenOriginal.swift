import SwiftUI

/// Open Original, the same on a tile, in the reader and on a video: the page opens in the browser, a file the
/// material was made from opens in Quick Look.
struct OpenOriginalButton: View {
    let itemID: String
    let page: URL?
    @Environment(LibraryModel.self) private var library

    var body: some View {
        switch library.original(of: itemID, page: page) {
        case let .web(url)?:
            Link(destination: url) { Label("Open Original", systemImage: "arrow.up.right") }
        case let .file(url)?:
            Button("Open Original", systemImage: "doc") { Task { await library.preview(url) } }
        case nil:
            EmptyView()
        }
    }
}
