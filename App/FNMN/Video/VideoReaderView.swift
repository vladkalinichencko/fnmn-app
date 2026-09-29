import AVKit
import FNMNCore
import SwiftUI
import WebKit

/// A video with its transcript. A downloaded file plays in the system player, otherwise YouTube plays embedded.
/// The second the viewer stopped at is saved exactly and survives restarts.
struct VideoReaderView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(MacLink.self) private var mac
    @Environment(ImportJobs.self) private var imports
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    let video: VideoCoordinator

    private var package: ImportPackage { video.package }
    private var materialID: String { package.material.id }

    private var videoID: String? {
        [package.blocks.first { $0.kind == .video }?.mediaURL, package.material.sourceURL]
            .compactMap { $0 }.compactMap(YouTube.videoID(in:)).first
    }

    private var download: ImportJob? {
        imports.jobs.first { if case let .videoFile(itemID, _) = $0.input { itemID == materialID } else { false } }
    }

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = horizontalSizeClass == .regular && geometry.size.width > geometry.size.height
            let showsCaptions = video.state.showsCaptions
            Group {
                if sideBySide {
                    HStack(alignment: .top, spacing: 0) {
                        player.frame(maxWidth: showsCaptions ? geometry.size.width * 0.58 : .infinity, maxHeight: .infinity)
                        if showsCaptions { captions.frame(width: geometry.size.width * 0.42, height: geometry.size.height) }
                    }
                } else {
                    VStack(spacing: 0) {
                        player
                        if showsCaptions { captions }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Tokens.canvas)
        .navigationTitle(package.material.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Toggle(
                video.state.showsCaptions ? "Hide Captions" : "Show Captions",
                systemImage: "captions.bubble",
                isOn: video.binding(\.showsCaptions, send: VideoAction.showCaptions)
            )
            Menu("More", systemImage: "ellipsis") { videoMenu }
        }
        .onDisappear { video.send(.left) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { video.send(.left) } }
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
        let video = video
        if let file = library.videoFile(materialID) {
            SystemPlayer(
                url: file,
                start: video.start,
                seekTo: video.state.seekTo,
                onSeekDone: { video.send(.seekDone) },
                onSeconds: { video.send(.played($0)) },
                onPause: { video.send(.paused) }
            )
            .aspectRatio(16 / 9, contentMode: .fit)
        } else {
            ZStack {
                if let videoID, let origin = mac.connection?.endpoint {
                    YouTubeEmbedView(
                        videoID: videoID,
                        origin: origin,
                        start: video.start,
                        seekTo: video.state.seekTo,
                        phase: video.state.embed,
                        onSeekDone: { video.send(.seekDone) },
                        onPhase: { video.send(.embed($0)) },
                        onSeconds: { video.send(.played($0)) },
                        onPause: { video.send(.paused) }
                    )
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .opacity(video.state.embed == .ready ? 1 : 0)
                }
                switch embedState {
                case .loading:
                    VideoPlaceholder { ProgressView() }
                case .ready:
                    EmptyView()
                case let .failed(message):
                    VStack(spacing: 0) {
                        VideoPlaceholder {
                            Image(systemName: "play.fill").font(.largeTitle).foregroundStyle(.tertiary)
                        }
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The embed needs a page address of our own for YouTube to accept it; it is the Mac's.
    /// The original and the download stay in the `···` menu, so the message only says what is missing.
    private var embedState: EmbedPhase {
        guard videoID != nil else { return .failed("Not a YouTube video") }
        guard mac.connection != nil else { return .failed("Connect the Mac in Settings to play here") }
        return video.state.embed
    }

    @ViewBuilder
    private var captions: some View {
        if video.cues.isEmpty {
            ContentUnavailableView("No captions", systemImage: "captions.bubble", description: Text("YouTube did not return captions. The video still plays."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let active = video.state.activeIndex
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(video.cues.enumerated()), id: \.element.id) { index, cue in
                        Button {
                            video.send(.jumped(toCue: index))
                        } label: {
                            CueRow(cue: cue, state: index < active ? .past : index == active ? .current : .ahead)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = cue.text }
                        }
                        .id(cue.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Tokens.gutter)
                .padding(.vertical, Tokens.gap)
                .animation(.snappy, value: active)
            }
            .background(Tokens.canvas)
            .scrollPosition(id: video.binding(\.pinnedCue, send: VideoAction.pinned), anchor: .center)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { video.send(.scrolledByHand) }
            }
        }
    }
}

/// One line of the transcript, in the reader's font: the line being spoken sits on a plate like a paragraph,
/// what is already said fades back, and each line keeps its time at the side.
private struct CueRow: View {
    enum State { case past, current, ahead }
    let cue: VideoCue
    let state: State
    @AppStorage(ReaderAppearance.fontKey) private var readerFont = ReaderFont.system

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Duration.seconds(cue.startSeconds).formatted(.time(pattern: cue.startSeconds >= 3600 ? .hourMinuteSecond : .minuteSecond)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(state == .current ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .frame(minWidth: 36, alignment: .trailing)
            Text(cue.text)
                .font(.system(.body, design: readerFont.design))
                .foregroundStyle(state == .past ? .secondary : .primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            if state == .current {
                Color.clear.plate(cornerRadius: Tokens.concentric(Tokens.plateRadius, inset: 8))
            }
        }
        .contentShape(.rect)
    }
}

/// Where the video will be: a gray frame of the video's shape, holding a spinner or a play symbol.
private struct VideoPlaceholder<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        RoundedRectangle(cornerRadius: Tokens.plateRadius, style: .continuous)
            .fill(.quaternary)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(content: content)
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.gap)
    }
}

/// The system player for a downloaded video, with picture in picture and exact seeking.
private struct SystemPlayer: UIViewControllerRepresentable {
    let url: URL
    let start: Double
    let seekTo: Double?
    let onSeekDone: @MainActor () -> Void
    let onSeconds: @MainActor (Double) -> Void
    let onPause: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let player = AVPlayer(url: url)
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        context.coordinator.observe(player, seconds: onSeconds, paused: onPause)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        guard let value = seekTo, let player = controller.player else { return }
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        let done = onSeekDone
        Task { @MainActor in done() }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stop(controller.player)
    }

    final class Coordinator {
        private var timeObserver: Any?
        private var statusObserver: NSKeyValueObservation?

        /// Both observers are called on the main queue, where the reader's state lives.
        func observe(_ player: AVPlayer, seconds: @escaping @MainActor (Double) -> Void, paused: @escaping @MainActor () -> Void) {
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
                MainActor.assumeIsolated { seconds(time.seconds) }
            }
            statusObserver = player.observe(\.timeControlStatus) { player, _ in
                guard player.timeControlStatus == .paused else { return }
                Task { @MainActor in paused() }
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
    let seekTo: Double?
    let phase: EmbedPhase
    let onSeekDone: @MainActor () -> Void
    let onPhase: @MainActor (EmbedPhase) -> Void
    let onSeconds: @MainActor (Double) -> Void
    let onPause: @MainActor () -> Void

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
        context.coordinator.onSeconds = onSeconds
        context.coordinator.onPhase = onPhase
        context.coordinator.onPause = onPause
        if context.coordinator.loaded != videoID {
            context.coordinator.loaded = videoID
            context.coordinator.resumeAt = start
            view.loadHTMLString(Self.page(videoID: videoID, origin: origin, start: start), baseURL: origin)
        }
        if phase == .ready, let value = seekTo ?? context.coordinator.takeResume() {
            let done = seekTo == nil ? nil : onSeekDone
            view.evaluateJavaScript("window.fnmnSeek(\(value));") { _, _ in
                if let done { Task { @MainActor in done() } }
            }
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "fnmn")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loaded: String?
        var resumeAt: Double?
        var onSeconds: (@MainActor (Double) -> Void)?
        var onPhase: (@MainActor (EmbedPhase) -> Void)?
        var onPause: (@MainActor () -> Void)?

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
                var last = -1;
                setInterval(function(){
                  var seconds = player.getCurrentTime();
                  if (seconds === last) return;
                  last = seconds;
                  post({kind:"time", seconds: seconds});
                }, 500);
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
