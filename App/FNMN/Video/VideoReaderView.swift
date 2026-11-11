import AVKit
import FNMNCore
import SwiftUI
import WebKit

struct VideoReaderView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ServerLink.self) private var server
    @Environment(ImportJobs.self) private var imports
    @Environment(\.scenePhase) private var scenePhase
    let video: VideoCoordinator
    @State private var downloading: URL?
    @State private var stageHeight: CGFloat = 0

    private var hasCaptions: Bool { !video.cues.isEmpty }
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
            let sideBySide = geometry.size.width > geometry.size.height
            let showsCaptions = hasCaptions && video.state.showsCaptions
            Group {
                if sideBySide {
                    HStack(spacing: 0) {
                        stage
                            .padding(Tokens.gutter)
                            .frame(width: showsCaptions ? geometry.size.width * 0.58 : geometry.size.width, height: geometry.size.height)
                        if showsCaptions {
                            captions
                                .frame(width: geometry.size.width * 0.42, height: geometry.size.height)
                                .transition(.opacity)
                        }
                    }
                } else {
                    ZStack(alignment: showsCaptions ? .top : .center) {
                        if showsCaptions {
                            captions
                                .contentMargins(.top, stageHeight + Tokens.gap, for: .scrollContent)
                                .contentMargins(.top, stageHeight, for: .scrollIndicators)
                                .transition(.opacity)
                        }
                        stage
                            .padding(.horizontal, Tokens.gutter)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stageHeight = $0 }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showsCaptions ? .top : .center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.smooth, value: showsCaptions)
        }
        .modifier(ReaderAppearanceModifier())
        .navigationTitle(package.material.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Toggle(
                video.state.showsCaptions ? "Hide Captions" : "Show Captions",
                systemImage: "captions.bubble",
                isOn: hasCaptions ? video.binding(\.showsCaptions, send: VideoAction.showCaptions) : .constant(false)
            )
            .disabled(!hasCaptions)
            Menu("More", systemImage: "ellipsis") { videoMenu }
        }
        .onDisappear { video.send(.left) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { video.send(.left) } }
        .task { _ = server.savedConnection() }
    }

    @ViewBuilder
    private var videoMenu: some View {
        ReaderAppearanceControls()
        if library.originalFile(materialID) != nil {
            Button("Remove Download", systemImage: "trash") {
                Task { await library.removeOriginal(of: materialID) }
            }
        } else if !Features.videoDownload {
            EmptyView()
        } else if let download {
            switch download.phase {
            case let .preparing(step, _):
                Text(step.text)
            case let .failed(message, _):
                Button("Try Download Again", systemImage: "arrow.clockwise") { imports.send(.retry(download.id)) }
                Text(message)
            }
        } else if let page = package.material.sourceURL {
            Button("Download", systemImage: "arrow.down.circle") {
                imports.send(.submit(.videoFile(itemID: materialID, url: page), id: UUID()))
            }
        }
        OpenOriginalButton(itemID: materialID, page: package.material.sourceURL)
    }

    private var stage: some View {
        VStack(spacing: 0) {
            player
                .aspectRatio(16 / 9, contentMode: .fit)
            if case let .failed(message) = embedState, library.originalFile(materialID) == nil {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(Tokens.tilePadding)
            }
        }
        .clipShape(.rect(cornerRadius: Tokens.plateRadius, style: .continuous))
        .plate(cornerRadius: Tokens.plateRadius)
    }

    @ViewBuilder
    private var player: some View {
        let video = video
        switch source {
        case let .coming(file):
            VideoPlaceholder { Loading() }
                .task(id: file) {
                    downloading = file
                    defer { downloading = nil }
                    do {
                        try await CloudFolder.download(file, timeout: .seconds(1800))
                    } catch CloudFolderError.notDownloaded(_, _) {
                        library.failure = CloudFolderError.notDownloaded(count: 1, name: package.material.title).localizedDescription
                    } catch {
                        library.failure = error.localizedDescription
                    }
                }
        case let .local(file):
            SystemPlayer(
                url: file,
                start: video.start,
                seekTo: video.state.seekTo,
                onSeekDone: { video.send(.seekDone) },
                onSeconds: { video.send(.played($0)) },
                onPause: { video.send(.paused) }
            )
            .aspectRatio(16 / 9, contentMode: .fit)
        case .embed:
            ZStack {
                if let videoID, let origin = server.connection?.endpoint {
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
                    VideoPlaceholder { Loading() }
                case .ready:
                    EmptyView()
                case .failed:
                    VideoPlaceholder {
                        Image(systemName: "play.fill").font(.largeTitle).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var source: VideoSource {
        VideoSource.of(original: library.originalFile(materialID), downloading: downloading, onDevice: CloudFolder.isLocal)
    }

    private var embedState: EmbedPhase {
        guard videoID != nil else { return .failed("Not a YouTube video") }
        guard server.hasReadConnection else {
            return .loading
        }
        guard server.connection != nil else { return .failed("Connect the server in Settings to play here") }
        return video.state.embed
    }

    private var captions: some View {
        let active = video.state.activeIndex
        return ScrollView {
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
            .backgroundPreferenceValue(CurrentCueBounds.self) { bounds in
                GeometryReader { proxy in
                    if let bounds {
                        let frame = proxy[bounds]
                        Color.clear
                            .plate(cornerRadius: Tokens.concentric(Tokens.plateRadius, inset: 8))
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                            .transition(.opacity)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.gap)
        }
        .scrollPosition(id: video.binding(\.pinnedCue, send: VideoAction.pinned), anchor: .center)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { video.send(.scrolledByHand) }
        }
    }
}

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
                .font(readerFont.font(.body))
                .foregroundStyle(state == .past ? .secondary : .primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .anchorPreference(key: CurrentCueBounds.self, value: .bounds) { state == .current ? $0 : nil }
        .contentShape(.rect)
    }
}

private struct CurrentCueBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct VideoPlaceholder<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(content: content)
    }
}

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
        guard let value = seekTo, let player = controller.player else {
            return
        }
        let done = onSeekDone
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            guard finished else {
                return
            }
            Task { @MainActor in done() }
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stop(controller.player)
    }

    final class Coordinator {
        private var timeObserver: Any?
        private var statusObserver: NSKeyValueObservation?

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

struct YouTubeEmbedView: UIViewRepresentable {
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
            context.coordinator.start(videoID, origin: origin, start: start, in: view)
        }
        if phase == .ready {
            if let value = seekTo {
                let done = onSeekDone
                view.evaluateJavaScript("window.fnmnSeek(\(value));") { _, _ in
                    Task { @MainActor in done() }
                }
            } else if let value = context.coordinator.takeResume() {
                view.evaluateJavaScript("window.fnmnCue(\(value));")
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
        private var generation = WebGeneration()
        private var navigation: WKNavigation?

        func start(_ videoID: String, origin: URL, start: Double, in view: WKWebView) {
            loaded = videoID
            resumeAt = start
            let generation = generation.next()
            navigation = view.loadHTMLString(
                page(videoID: videoID, origin: origin, start: start, generation: generation),
                baseURL: origin
            )
        }

        func takeResume() -> Double? {
            defer { resumeAt = nil }
            return resumeAt
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else {
                return
            }
            guard generation.accepts(body["generation"] as? Int) else {
                return
            }
            switch kind {
            case "ready": onPhase?(.ready)
            case "time": if let value = body["seconds"] as? Double { onSeconds?(value) }
            case "paused": onPause?()
            case "failed": onPhase?(.failed("YouTube refused to play this video here (error \(body["code"] ?? "")). \(Features.videoDownload ? "Download it or open it on YouTube." : "Open it on YouTube.")"))
            default: break
            }
        }

        func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failed(navigation, error)
        }

        func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failed(navigation, error)
        }

        private func failed(_ failed: WKNavigation?, _ error: Error) {
            guard let navigation, failed === navigation else {
                return
            }
            onPhase?(.failed(error.localizedDescription))
        }
    }

    static func page(videoID: String, origin: URL, start: Double, generation: Int) -> String {
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
        function post(payload){ payload.generation = \(generation); window.webkit.messageHandlers.fnmn.postMessage(payload); }
        window.fnmnSeek = function(){};
        window.fnmnCue = function(){};
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
                window.fnmnCue = function(seconds){ player.cueVideoById({videoId: "\(videoID)", startSeconds: seconds}); };
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
