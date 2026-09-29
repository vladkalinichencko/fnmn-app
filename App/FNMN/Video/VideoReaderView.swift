import AVKit
import FNMNCore
import SwiftUI
import WebKit

private struct VideoCue: Identifiable, Equatable {
    let id: String
    let startSeconds: Double
    let text: String
}

enum EmbedPhase: Equatable {
    case loading
    case ready
    case failed(String)
}

/// A video with its transcript. A downloaded file plays in the system player, otherwise YouTube plays embedded.
/// The second the viewer stopped at is saved exactly and survives restarts.
struct VideoReaderView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(MacLink.self) private var mac
    @Environment(ImportJobs.self) private var imports
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    let package: ImportPackage
    @State private var seconds = 0.0
    @State private var savedAt = Date.distantPast
    @State private var showCaptions = true
    @State private var seekTo: Double?
    @State private var phase = EmbedPhase.loading
    @State private var pinnedCue: String?
    @State private var followsCaptions = true
    @State private var resumeFollowing: Task<Void, Never>?

    private var materialID: String { package.material.id }

    private var cues: [VideoCue] {
        package.blocks.compactMap { block in
            guard block.kind == .transcript, let start = block.startSeconds else { return nil }
            let text = block.html.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return VideoCue(id: block.id, startSeconds: start, text: text)
        }
    }

    private var videoID: String? {
        [package.blocks.first { $0.kind == .video }?.mediaURL, package.material.sourceURL]
            .compactMap { $0 }.compactMap(YouTube.videoID(in:)).first
    }

    private var activeCueID: String? {
        (cues.last { $0.startSeconds <= seconds + 0.05 } ?? cues.first)?.id
    }

    private var savedSeconds: Double {
        library.snapshot.positions[materialID]?.videoSeconds ?? 0
    }

    private var download: ImportJob? {
        imports.jobs.first { if case let .videoFile(itemID, _) = $0.input { itemID == materialID } else { false } }
    }

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = horizontalSizeClass == .regular && geometry.size.width > geometry.size.height
            Group {
                if sideBySide {
                    HStack(alignment: .top, spacing: 0) {
                        player.frame(maxWidth: showCaptions ? geometry.size.width * 0.58 : .infinity, maxHeight: .infinity)
                        if showCaptions { captions.frame(width: geometry.size.width * 0.42, height: geometry.size.height) }
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Toggle(showCaptions ? "Hide Captions" : "Show Captions", systemImage: "captions.bubble", isOn: $showCaptions)
            Menu("More", systemImage: "ellipsis") { videoMenu }
        }
        .onAppear {
            seconds = savedSeconds
            pinnedCue = activeCueID
        }
        .onDisappear { save(force: true) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { save(force: true) } }
        .onChange(of: seconds) { _, _ in
            if followsCaptions { pinnedCue = activeCueID }
            save(force: false)
        }
    }

    @ViewBuilder
    private var videoMenu: some View {
        if library.videoFile(materialID) != nil {
            Button("Remove Download", systemImage: "trash") {
                Task { await library.apply(.removeVideoFile(itemID: materialID)) }
            }
        } else if let download {
            switch download.phase {
            case let .preparing(step):
                Text(step.text)
            case let .failed(message):
                Button("Try Download Again", systemImage: "arrow.clockwise") { imports.send(.retry(download.id)) }
                Text(message)
            }
        } else if videoID != nil {
            Button("Download", systemImage: "arrow.down.circle") {
                imports.send(.submit(.videoFile(itemID: materialID, url: package.material.sourceURL), id: UUID()))
            }
        }
        Link(destination: package.material.sourceURL) { Label("Open Original", systemImage: "arrow.up.right") }
    }

    @ViewBuilder
    private var player: some View {
        if let file = library.videoFile(materialID) {
            SystemPlayer(url: file, start: savedSeconds, seekTo: $seekTo, seconds: $seconds, onPause: { save(force: true) })
                .aspectRatio(16 / 9, contentMode: .fit)
        } else {
            ZStack {
                if let videoID, let origin = mac.connection?.endpoint {
                    YouTubeEmbedView(
                        videoID: videoID,
                        origin: origin,
                        start: savedSeconds,
                        seekTo: $seekTo,
                        seconds: $seconds,
                        phase: $phase,
                        onPause: { save(force: true) }
                    )
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .opacity(phase == .ready ? 1 : 0)
                }
                switch embedState {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                case .ready:
                    EmptyView()
                case let .failed(message):
                    ContentUnavailableView {
                        Label(package.material.title, systemImage: "play.rectangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Link("Open on YouTube", destination: package.material.sourceURL)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The embed needs a page address of our own for YouTube to accept it; it is the Mac's.
    private var embedState: EmbedPhase {
        guard videoID != nil else { return .failed("This address has no YouTube video.") }
        guard mac.connection != nil else { return .failed("Set up the Mac in Settings to play videos here, or download the video.") }
        return phase
    }

    private var captions: some View {
        Group {
            if cues.isEmpty {
                ContentUnavailableView("No captions", systemImage: "captions.bubble", description: Text("YouTube did not return captions. The video still plays."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(cues) { cue in
                            Button {
                                seekTo = cue.startSeconds
                                seconds = cue.startSeconds
                                save(force: true)
                                followsCaptions = true
                            } label: {
                                Text(cue.text)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(cue.id == activeCueID ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .id(cue.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding()
                }
                .scrollPosition(id: $pinnedCue, anchor: .center)
                .onScrollPhaseChange { _, phase in
                    guard phase == .interacting else { return }
                    pauseFollowing()
                }
            }
        }
    }

    /// Scrolling the transcript by hand stops it following the video for a few seconds.
    private func pauseFollowing() {
        followsCaptions = false
        resumeFollowing?.cancel()
        resumeFollowing = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            followsCaptions = true
        }
    }

    /// Writes the exact second on pause, seek, leaving and backgrounding, and every two seconds while playing.
    private func save(force: Bool) {
        guard force || Date.now.timeIntervalSince(savedAt) >= 2 else { return }
        guard abs(seconds - savedSeconds) > 0.01 else { return }
        savedAt = .now
        let blockID = package.blocks.first { $0.kind == .video }?.id ?? materialID
        let progress = cues.isEmpty ? 0 : Double((cues.firstIndex { $0.id == activeCueID } ?? -1) + 1) / Double(cues.count)
        let position = ReadingPosition(blockID: blockID, videoSeconds: seconds)
        Task { await library.apply(.savePosition(position, itemID: materialID, progress: progress)) }
    }
}

/// The system player for a downloaded video, with picture in picture and exact seeking.
private struct SystemPlayer: UIViewControllerRepresentable {
    let url: URL
    let start: Double
    @Binding var seekTo: Double?
    @Binding var seconds: Double
    let onPause: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let player = AVPlayer(url: url)
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        context.coordinator.observe(player, seconds: { seconds = $0 }, paused: onPause)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        guard let value = seekTo, let player = controller.player else { return }
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        DispatchQueue.main.async { seekTo = nil }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stop(controller.player)
    }

    final class Coordinator {
        private var timeObserver: Any?
        private var statusObserver: NSKeyValueObservation?

        func observe(_ player: AVPlayer, seconds: @escaping (Double) -> Void, paused: @escaping () -> Void) {
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
                seconds(time.seconds)
            }
            statusObserver = player.observe(\.timeControlStatus) { player, _ in
                guard player.timeControlStatus == .paused else { return }
                DispatchQueue.main.async(execute: paused)
            }
        }

        func stop(_ player: AVPlayer?) {
            if let timeObserver { player?.removeTimeObserver(timeObserver) }
            statusObserver = nil
            player?.pause()
        }
    }
}

/// YouTube's player on a local page whose address is the Mac's: YouTube requires an embedding page it can identify.
private struct YouTubeEmbedView: UIViewRepresentable {
    let videoID: String
    let origin: URL
    let start: Double
    @Binding var seekTo: Double?
    @Binding var seconds: Double
    @Binding var phase: EmbedPhase
    let onPause: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
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
        context.coordinator.onPause = onPause
        if context.coordinator.loaded != videoID {
            context.coordinator.loaded = videoID
            context.coordinator.resumeAt = start
            phase = .loading
            view.loadHTMLString(Self.page(videoID: videoID, origin: origin, start: start), baseURL: origin)
        }
        if phase == .ready, let value = seekTo ?? context.coordinator.takeResume() {
            view.evaluateJavaScript("window.fnmnSeek(\(value));") { _, _ in
                DispatchQueue.main.async { if self.seekTo == value { self.seekTo = nil } }
            }
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "fnmn")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loaded: String?
        var resumeAt: Double?
        var onSeconds: ((Double) -> Void)?
        var onPhase: ((EmbedPhase) -> Void)?
        var onPause: (() -> Void)?

        /// The exact saved second, applied once the player is ready; the page itself can only start on a whole second.
        func takeResume() -> Double? {
            defer { resumeAt = nil }
            return resumeAt
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
            switch kind {
            case "ready": onPhase?(.ready)
            case "time": if let value = body["seconds"] as? Double { onSeconds?(value) }
            case "paused": onPause?()
            case "failed": onPhase?(.failed("YouTube refused to play this video here (error \(body["code"] ?? "")). Download it or open it on YouTube."))
            default: break
            }
        }

        func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onPhase?(.failed(error.localizedDescription))
        }

        func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onPhase?(.failed(error.localizedDescription))
        }
    }

    private static func page(videoID: String, origin: URL, start: Double) -> String {
        let startAt = max(0, Int(start.rounded(.down)))
        let host = origin.scheme.map { "\($0)://\(origin.host() ?? "")" } ?? origin.absoluteString
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;background:#000;height:100%}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe id="player" referrerpolicy="strict-origin-when-cross-origin" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen
          src="https://www.youtube.com/embed/\(videoID)?enablejsapi=1&playsinline=1&rel=0&start=\(startAt)&origin=\(host)"></iframe>
        <script>
        function post(payload){ window.webkit.messageHandlers.fnmn.postMessage(payload); }
        window.fnmnSeek = function(){};
        var tag = document.createElement('script');
        tag.src = "https://www.youtube.com/iframe_api";
        tag.onerror = function(){ post({kind:"failed", code:"api"}); };
        document.head.appendChild(tag);
        var player;
        function onYouTubeIframeAPIReady(){
          player = new YT.Player('player', {
            events: {
              onReady: function(){
                window.fnmnSeek = function(seconds){ player.seekTo(seconds, true); };
                post({kind:"ready"});
                setInterval(function(){ post({kind:"time", seconds: player.getCurrentTime()}); }, 500);
              },
              onStateChange: function(event){ if (event.data === YT.PlayerState.PAUSED) post({kind:"paused"}); },
              onError: function(event){ post({kind:"failed", code: String(event.data)}); }
            }
          });
        }
        </script></body></html>
        """
    }
}
