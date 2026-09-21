import SwiftUI
import WebKit

struct BlockWebView: UIViewRepresentable {
    let block: Block
    let sourceURL: URL
    let resumeSeconds: Double?
    let scenePhase: ScenePhase
    let onVideoTime: (Double) -> Void

    init(
        block: Block,
        sourceURL: URL,
        resumeSeconds: Double? = nil,
        scenePhase: ScenePhase = .active,
        onVideoTime: @escaping (Double) -> Void = { _ in }
    ) {
        self.block = block
        self.sourceURL = sourceURL
        self.resumeSeconds = resumeSeconds
        self.scenePhase = scenePhase
        self.onVideoTime = onVideoTime
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onVideoTime: onVideoTime)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = block.kind == .video
        configuration.userContentController.add(context.coordinator, name: "videoTime")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.scrollView.contentInsetAdjustmentBehavior = .automatic
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if block.kind == .video, scenePhase != .active {
            context.coordinator.readTime(from: view)
        }
        guard context.coordinator.loadedBlockID != block.id else { return }
        context.coordinator.loadedBlockID = block.id
        let body: String
        if block.kind == .video, let mediaURL = block.mediaURL {
            let videoID = mediaURL.pathComponents.last ?? ""
            body = """
            <div id="player"></div><script src="https://www.youtube.com/iframe_api"></script><script>
            let player;
            function reportTime() { if (player?.getCurrentTime) window.webkit.messageHandlers.videoTime.postMessage(player.getCurrentTime()); }
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', { videoId: '\(videoID)', playerVars: { playsinline: 1, origin: 'https://local.fnmn.reader' }, events: {
                onReady: event => event.target.seekTo(\(resumeSeconds ?? 0), true),
                onStateChange: reportTime
              }});
              setInterval(reportTime, 5000);
            }
            document.addEventListener('visibilitychange', reportTime);
            </script>
            """
        } else {
            body = block.html
        }
        let page = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        :root { color-scheme: light dark; font: -apple-system-body; }
        body { margin: 20px; overflow-wrap: anywhere; }
        img, video, iframe { max-width: 100%; height: auto; }
        iframe { width: 100%; aspect-ratio: 16/9; border: 0; }
        pre, math { overflow-x: auto; }
        a { color: -apple-system-link; }
        </style><body>\(body)</body>
        """
        let baseURL = block.kind == .video ? URL(string: "https://local.fnmn.reader")! : sourceURL
        view.loadHTMLString(page, baseURL: baseURL)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.readTime(from: view) {
            view.configuration.userContentController.removeScriptMessageHandler(forName: "videoTime")
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onVideoTime: (Double) -> Void
        var loadedBlockID: String?
        init(onVideoTime: @escaping (Double) -> Void) {
            self.onVideoTime = onVideoTime
        }

        func readTime(from view: WKWebView, completion: (() -> Void)? = nil) {
            view.evaluateJavaScript("player?.getCurrentTime()") { [onVideoTime] value, _ in
                if let seconds = value as? Double {
                    onVideoTime(seconds)
                }
                completion?()
            }
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if let seconds = message.body as? Double {
                onVideoTime(seconds)
            }
        }
    }
}
