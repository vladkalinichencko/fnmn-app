import FNMNCore
import SwiftUI
import WebKit

enum CropPhase: Equatable {
    case loading
    case shown(CGFloat)
    case failed(String)
}

struct LiveCropView: View {
    let url: URL
    let selector: String?
    @State private var phase = CropPhase.loading
    /// The height each figure last showed at. The lazy column lets a figure go once it scrolls far away and makes it
    /// anew when it comes back; starting at the plate's loading height, it would grow while the column scrolls up
    /// to it and push the text below it down.
    private static var shownHeights: [String: CGFloat] = [:]

    var body: some View {
        ZStack {
            LiveCropWebView(url: url, selector: selector, phase: $phase)
                .frame(height: height ?? 0)
                .opacity(isShown ? 1 : 0)
            if case .loading = phase {
                Loading()
            }
            // A figure that did not come takes one line of the plate, set in from its edges like a paragraph.
            if case let .failed(message) = phase {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Tokens.tilePadding)
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: Tokens.plateRadius, style: .continuous))
        .plate(cornerRadius: Tokens.plateRadius)
        .onChange(of: phase) {
            if case let .shown(value) = phase { Self.shownHeights[key] = value }
        }
    }

    private var key: String { url.absoluteString + "#" + (selector ?? "") }

    private var isShown: Bool {
        if case .shown = phase { return true }
        return false
    }

    /// Nil once the figure failed: the plate is as tall as the message.
    private var height: CGFloat? {
        switch phase {
        case let .shown(value): max(value, 44)
        case .loading: Self.shownHeights[key].map { max($0, 44) } ?? Tokens.embedHeight
        case .failed: nil
        }
    }
}

struct LiveCropWebView: UIViewRepresentable {
    let url: URL
    let selector: String?
    @Binding var phase: CropPhase

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "crop")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        // A figure wider or taller than its frame is moved by the finger; one that fits stays still.
        view.scrollView.bounces = false
        view.scrollView.isDirectionalLockEnabled = true
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = false
        // The phase starts as `.loading`, so the first load needs no state change from the update pass.
        context.coordinator.start(url, selector: selector, in: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onPhase = { phase = $0 }
        guard context.coordinator.loaded != url else { return }
        context.coordinator.start(url, selector: selector, in: view)
        // A view update must not write state; the new page's phase is set right after it.
        Task { @MainActor in phase = .loading }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {        view.configuration.userContentController.removeScriptMessageHandler(forName: "crop")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loaded: URL?
        var onPhase: ((CropPhase) -> Void)?
        /// The page on screen: its number comes back with every message, and its navigation owns the failures.
        private var generation = WebGeneration()
        private var navigation: WKNavigation?

        /// Starts the page and stamps it with a new number, so a callback from the page it replaces is dropped.
        func start(_ url: URL, selector: String?, in view: WKWebView) {
            loaded = url
            let generation = generation.next()
            let controller = view.configuration.userContentController
            // The figure is cut out as soon as the page's markup is parsed, not after every picture, font and script
            // of the whole page has loaded; it keeps reporting its height while the rest arrives.
            controller.removeAllUserScripts()
            controller.addUserScript(WKUserScript(
                source: Self.script(selector: selector, generation: generation),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
            if url.isFileURL {
                navigation = view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                navigation = view.load(URLRequest(url: url))
            }
        }

        func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failed(navigation, error)
        }

        func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failed(navigation, error)
        }

        /// A load the app has replaced fails as cancelled, and that failure is not the page's.
        private func failed(_ failed: WKNavigation?, _ error: Error) {
            guard let navigation, failed === navigation else {
                return
            }
            onPhase?(.failed(error.localizedDescription))
        }

        func webView(
            _ view: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            navigationAction.navigationType == .linkActivated ? .cancel : .allow
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else {
                return
            }
            guard generation.accepts(body["generation"] as? Int) else {
                return
            }
            if body["kind"] as? String == "missing" {
                onPhase?(.failed("The figure is not on this page."))
                return
            }
            let height = body["height"] as? Double ?? (body["height"] as? Int).map(Double.init)
            if let height, height > 0 {
                onPhase?(.shown(CGFloat(height)))
            }
        }

        static func script(selector: String?, generation: Int) -> String {
            let encoded = (try? JSONEncoder().encode(selector)) ?? Data("null".utf8)
            let literal = String(decoding: encoded, as: UTF8.self)
            return """
            (function crop() {
              const selector = \(literal);
              const generation = \(generation);
              function report(height) {
                window.webkit.messageHandlers.crop.postMessage({kind: "height", height: height, generation: generation});
              }
              if (!selector) {
                // A whole page, such as an app the article carries, grows as its styles and scripts arrive.
                const page = () => report(Math.ceil(document.body.getBoundingClientRect().height));
                page();
                if (window.ResizeObserver) new ResizeObserver(page).observe(document.body);
                return;
              }
              const target = document.querySelector(selector);
              if (!target) {
                // A page that builds the figure with its own scripts has it only once it has loaded.
                if (document.readyState !== "complete" && !window.__fnmnCropWaited) {
                  window.__fnmnCropWaited = true;
                  window.addEventListener("load", crop);
                  return;
                }
                window.webkit.messageHandlers.crop.postMessage({kind: "missing", generation: generation});
                return;
              }
              const keep = new Set();
              let node = target;
              while (node) { keep.add(node); node = node.parentElement; }
              for (const el of document.body.querySelectorAll("*")) {
                if (keep.has(el) || target.contains(el)) continue;
                el.style.setProperty("display", "none", "important");
              }
              node = target.parentElement;
              while (node) {
                node.style.setProperty("margin", "0", "important");
                node.style.setProperty("padding", "0", "important");
                node.style.setProperty("border", "0", "important");
                node.style.setProperty("min-height", "0", "important");
                node = node.parentElement;
              }
              function fit() {
                const box = target.getBoundingClientRect();
                const available = document.documentElement.clientWidth || box.width;
                const scale = box.width > available && box.width > 0 ? available / box.width : 1;
                target.style.transformOrigin = "top left";
                target.style.transform = scale < 1 ? "scale(" + scale + ")" : "";
                report(Math.ceil(target.getBoundingClientRect().height));
              }
              fit();
              if (window.ResizeObserver) new ResizeObserver(fit).observe(target);
            })();
            """
        }
    }
}
