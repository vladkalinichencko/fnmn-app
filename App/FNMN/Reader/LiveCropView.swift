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

    var body: some View {
        ZStack {
            LiveCropWebView(url: url, selector: selector, phase: $phase)
                .frame(height: height)
                .opacity(isShown ? 1 : 0)
            if case .loading = phase {
                ProgressView("Opening the figure")
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
            if case let .failed(message) = phase {
                Text(message)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: height)
    }

    private var isShown: Bool {
        if case .shown = phase { return true }
        return false
    }

    private var height: CGFloat {
        if case let .shown(value) = phase { return max(value, 44) }
        return 180
    }
}

private struct LiveCropWebView: UIViewRepresentable {
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
        // The figure is cut out as soon as the page's markup is parsed, not after every picture, font and script
        // of the whole page has loaded; it keeps reporting its height while the rest arrives.
        configuration.userContentController.addUserScript(WKUserScript(
            source: Coordinator.script(selector: selector),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onPhase = { phase = $0 }
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        phase = .loading
        view.load(URLRequest(url: url))
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "crop")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loaded: URL?
        var onPhase: ((CropPhase) -> Void)?

        func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onPhase?(.failed(error.localizedDescription))
        }

        func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onPhase?(.failed(error.localizedDescription))
        }

        func webView(
            _ view: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            navigationAction.navigationType == .linkActivated ? .cancel : .allow
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if body["kind"] as? String == "missing" {
                onPhase?(.failed("The figure is not on this page."))
                return
            }
            let height = body["height"] as? Double ?? (body["height"] as? Int).map(Double.init)
            if let height, height > 0 {
                onPhase?(.shown(CGFloat(height)))
            }
        }

        static func script(selector: String?) -> String {
            let encoded = (try? JSONEncoder().encode(selector)) ?? Data("null".utf8)
            let literal = String(decoding: encoded, as: UTF8.self)
            return """
            (function crop() {
              const selector = \(literal);
              function report(height) {
                window.webkit.messageHandlers.crop.postMessage({kind: "height", height: height});
              }
              if (!selector) {
                report(document.documentElement.scrollHeight);
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
                window.webkit.messageHandlers.crop.postMessage({kind: "missing"});
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
