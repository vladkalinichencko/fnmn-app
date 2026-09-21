import SwiftUI
import WebKit

struct BookWebView: UIViewRepresentable {
    let storage: URL
    let book: String
    let contentFile: String
    let assetsDirectory: String
    let heading: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.scrollView.contentInsetAdjustmentBehavior = .automatic
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let key = "\(book)|\(contentFile)|\(heading ?? 0)"
        guard context.coordinator.loaded != key else { return }
        context.coordinator.loaded = key
        let page = storage.appending(path: "runtime").appending(path: "index.html")
        var components = URLComponents(url: page, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.queryItems = [
            URLQueryItem(name: "book", value: book),
            URLQueryItem(name: "content", value: contentFile),
            URLQueryItem(name: "assets", value: assetsDirectory),
            heading.map { URLQueryItem(name: "heading", value: String($0)) },
        ].compactMap { $0 }
        guard let url = components.url else { return }
        view.loadFileURL(url, allowingReadAccessTo: storage)
    }

    final class Coordinator {
        var loaded: String?
    }
}
