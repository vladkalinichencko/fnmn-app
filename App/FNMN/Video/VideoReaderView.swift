import FNMNCore
import SwiftUI
import WebKit

private struct VideoCue: Identifiable, Equatable {
    let id: String
    let startSeconds: Double
    let text: String
}

private enum EmbedPhase: Equatable {
    case loading
    case ready
    case failed
}

struct VideoReaderView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let package: ImportPackage
    @State private var seconds = 0.0
    @State private var savedSecond = -1
    @State private var showCaptions = true
    @State private var seekTo: Double?
    @State private var phase = EmbedPhase.loading
    @State private var pinnedCue: String?

    private var cues: [VideoCue] {
        package.blocks.compactMap { block in
            guard block.kind == .transcript, let start = block.startSeconds else { return nil }
            let text = block.html.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return VideoCue(id: block.id, startSeconds: start, text: text)
        }
    }

    private var videoBlock: Block? {
        package.blocks.first { $0.kind == .video }
    }

    private var playbackID: String? {
        let candidates = [videoBlock?.mediaURL, package.material.sourceURL].compactMap { $0 }
        return candidates.compactMap(YouTube.videoID(in:)).first
    }

    private var activeCueID: String? {
        guard let cue = cues.last(where: { $0.startSeconds <= seconds + 0.05 }) else { return cues.first?.id }
        return cue.id
    }

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = horizontalSizeClass == .regular && geometry.size.width > geometry.size.height
            Group {
                if sideBySide {
                    HStack(alignment: .top, spacing: 0) {
                        player.frame(maxWidth: showCaptions ? geometry.size.width * 0.58 : .infinity, maxHeight: .infinity)
                        if showCaptions {
                            captions.frame(width: geometry.size.width * 0.42, height: geometry.size.height)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        player
                        if showCaptions { captions }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(package.material.title)
        .toolbar {
            Toggle(showCaptions ? "Hide captions" : "Show captions", systemImage: "captions.bubble", isOn: $showCaptions)
            Link(destination: package.material.sourceURL) { Label("Open Original", systemImage: "arrow.up.right") }
        }
        .onAppear {
            if playbackID == nil { phase = .failed }
            restore()
        }
        .onDisappear { persist(seconds, force: true) }
        .onChange(of: seconds) { _, value in
            pinnedCue = activeCueID
            persist(value, force: false)
        }
        .onChange(of: activeCueID) { _, id in
            pinnedCue = id
        }
    }

    @ViewBuilder
    private var player: some View {
        ZStack {
            if let playbackID {
                YouTubeEmbedView(
                    videoID: playbackID,
                    startSeconds: library.snapshot.positions[package.material.id]?.videoSeconds ?? 0,
                    seekTo: $seekTo,
                    seconds: $seconds,
                    phase: $phase
                )
                .aspectRatio(16 / 9, contentMode: .fit)
                .opacity(phase == .failed ? 0 : 1)
            }
            if phase == .loading {
                ProgressView("Opening video")
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
            if phase == .failed {
                ContentUnavailableView {
                    Label(package.material.title, systemImage: "play.rectangle")
                } description: {
                    Text(package.material.byline ?? "Video")
                } actions: {
                    Link("Open on YouTube", destination: package.material.sourceURL)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.04))
    }

    private var captions: some View {
        Group {
            if cues.isEmpty {
                ContentUnavailableView("No caption text", systemImage: "captions.bubble", description: Text("YouTube did not return the captions. The video still plays."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(cues) { cue in
                            Button {
                                seekTo = cue.startSeconds
                                seconds = cue.startSeconds
                            } label: {
                                Text(cue.text)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(cue.id == activeCueID ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .id(cue.id)
                        }
                    }
                    .padding()
                }
                .scrollPosition(id: $pinnedCue, anchor: .center)
            }
        }
    }

    private func restore() {
        if let saved = library.snapshot.positions[package.material.id]?.videoSeconds {
            seconds = saved
            savedSecond = Int(saved.rounded(.down))
        }
        pinnedCue = activeCueID
    }

    private func persist(_ value: Double, force: Bool) {
        let second = Int(value.rounded(.down))
        guard force || second != savedSecond else { return }
        savedSecond = second
        let blockID = videoBlock?.id ?? package.blocks.first?.id ?? package.material.id
        let progress: Double
        if cues.isEmpty {
            progress = 0
        } else if let index = cues.firstIndex(where: { $0.id == activeCueID }) {
            progress = Double(index + 1) / Double(cues.count)
        } else {
            progress = 0
        }
        Task {
            await library.apply(.savePosition(
                ReadingPosition(blockID: blockID, videoSeconds: value),
                itemID: package.material.id,
                progress: progress
            ))
        }
    }

}

private struct YouTubeEmbedView: UIViewRepresentable {
    let videoID: String
    let startSeconds: Double
    @Binding var seekTo: Double?
    @Binding var seconds: Double
    @Binding var phase: EmbedPhase

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "fnmn")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onSeconds = { seconds = $0 }
        context.coordinator.onPhase = { phase = $0 }
        if context.coordinator.loaded != videoID {
            context.coordinator.loaded = videoID
            phase = .loading
            view.loadHTMLString(Self.page(videoID: videoID, start: startSeconds), baseURL: URL(string: "https://www.youtube.com"))
        }
        if phase == .ready, let value = seekTo {
            view.evaluateJavaScript("window.fnmnSeek && window.fnmnSeek(\(value));") { _, _ in
                DispatchQueue.main.async {
                    if self.seekTo == value { self.seekTo = nil }
                }
            }
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "fnmn")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loaded: String?
        var onSeconds: ((Double) -> Void)?
        var onPhase: ((EmbedPhase) -> Void)?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
            switch kind {
            case "ready":
                onPhase?(.ready)
            case "time":
                if let value = body["seconds"] as? Double {
                    onSeconds?(value)
                } else if let value = body["seconds"] as? Int {
                    onSeconds?(Double(value))
                }
            case "failed":
                onPhase?(.failed)
            default:
                break
            }
        }

        func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onPhase?(.failed)
        }

        func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onPhase?(.failed)
        }
    }

    private static func page(videoID: String, start: Double) -> String {
        let startAt = max(0, Int(start.rounded(.down)))
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;background:#000;height:100%}#player{position:absolute;inset:0}</style>
        </head><body>
        <div id="player"></div>
        <script>
        window.fnmnSeek = function(seconds){};
        function post(payload){ window.webkit.messageHandlers.fnmn.postMessage(payload); }
        var tag = document.createElement('script');
        tag.src = "https://www.youtube.com/iframe_api";
        tag.onerror = function(){ post({kind:"failed"}); };
        document.head.appendChild(tag);
        var player;
        function onYouTubeIframeAPIReady(){
          player = new YT.Player('player', {
            width: '100%', height: '100%',
            videoId: "\(videoID)",
            playerVars: { playsinline: 1, rel: 0, start: \(startAt), origin: 'https://www.youtube.com' },
            events: {
              onReady: function(){
                window.fnmnSeek = function(seconds){ try { player.seekTo(seconds, true); } catch(e){} };
                post({kind:"ready"});
                setInterval(function(){
                  try { post({kind:"time", seconds: player.getCurrentTime()}); } catch(e){}
                }, 500);
              },
              onError: function(){ post({kind:"failed"}); }
            }
          });
        }
        </script></body></html>
        """
    }
}
