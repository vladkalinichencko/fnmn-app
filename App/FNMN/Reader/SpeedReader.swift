import FNMNCore
import SwiftUI

enum SpeedPlayback: Equatable {
    case loading
    case paused
    case playing
    case resting(Int)
    case previewing(Int)
    case stopped
    case ended
}

enum SpeedRestMode: String, CaseIterable {
    case off, timed, manual
}

@MainActor @Observable
final class SpeedPlayer {
    private(set) var text: SpeedText?
    private(set) var frame = 0..<0
    private(set) var mode = SpeedPlayback.loading
    private(set) var furthest: Int?
    var wordsPerMinute = 250
    var pauseProfile = SpeedPauseProfile()
    var restMode = SpeedRestMode.timed
    var restSeconds = 1.6
    var wordsPerFrame = 1 {
        didSet {
            if mode != .playing, let text {
                frame = text.frame(at: frame.lowerBound, words: wordsPerFrame)
            }
        }
    }
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var plates: [Int] = []
    private(set) var backs = 0
    @ObservationIgnored private var reportedWords = 0
    @ObservationIgnored private var reportedBacks = 0
    @ObservationIgnored private var reportedAt = Date.now

    var isPlaying: Bool {
        mode == .playing
    }

    var resting: Int? {
        if case let .resting(block) = mode {
            return block
        }
        return nil
    }

    var previewed: Int? {
        if case let .previewing(block) = mode {
            return block
        }
        return nil
    }

    func load(_ document: ReaderDocument, from start: ReadingLine) async {
        guard text == nil else { return }
        reportedAt = .now
        plates = document.plates
        let text = await Task.detached(priority: .userInitiated) { SpeedText(document: document, from: start) }.value
        self.text = text
        frame = text.frame(at: 0, words: wordsPerFrame)
        enter(.paused)
    }

    var token: SpeedToken? {
        guard let text, text.tokens.indices.contains(frame.lowerBound) else { return nil }
        return text.tokens[frame.lowerBound]
    }

    var isAtEnd: Bool {
        guard let text else { return true }
        return frame.upperBound >= text.tokens.count
    }

    var shown: ReadingLine? {
        guard let text, let furthest else { return nil }
        return ReadingLine(piece: text.tokens[furthest].block, fraction: text.tokens[furthest].share)
    }

    func toggle() {
        if previewed != nil {
            enter(isAtEnd ? .ended : .playing)
            return
        }
        if resting != nil {
            continueResting()
            return
        }
        if isPlaying {
            pause()
        } else if token?.isStop == true {
            continuePastStop()
        } else {
            play()
        }
    }

    func play() {
        guard mode != .playing, previewed == nil, let token, !token.isStop else {
            return
        }
        markShown()
        enter(.playing)
    }

    func pause() {
        guard mode == .playing || resting != nil else {
            return
        }
        enter(.paused)
    }

    func sentenceBack() {
        guard let text else {
            return
        }
        let target = text.sentenceStart(before: frame.lowerBound)
        if target != frame.lowerBound {
            backs += 1
        }
        jump(to: target)
    }

    func summary(itemID: String, wordsPerMinute: Int, pauses: String) -> ReadingModeEvent {
        let shown = (furthest ?? -1) + 1
        let event = ReadingModeEvent(
            itemID: itemID,
            mode: .rsvp,
            wordsPerMinute: wordsPerMinute,
            pauses: pauses,
            words: max(shown - reportedWords, 0),
            backs: max(backs - reportedBacks, 0),
            startedAt: reportedAt,
            endedAt: .now
        )
        reportedWords = shown
        reportedBacks = backs
        reportedAt = .now
        return event
    }

    func sentenceForward() {
        guard let next = text?.sentenceStart(after: frame.lowerBound) else { return }
        jump(to: next)
    }

    func stepBack() {
        guard let block = previewed ?? resting ?? shownStop else {
            sentenceBack()
            return
        }
        guard let index = plates.firstIndex(of: block), index > plates.startIndex else {
            return
        }
        enter(.previewing(plates[index - 1]))
    }

    func stepForward() {
        guard let block = previewed ?? resting ?? shownStop else {
            sentenceForward()
            return
        }
        guard let index = plates.firstIndex(of: block), index + 1 < plates.endIndex else {
            return
        }
        enter(.previewing(plates[index + 1]))
    }

    private var shownStop: Int? {
        token?.isStop == true ? token?.block : nil
    }

    func continuePastStop() {
        guard !isAtEnd else { return }
        show(frame.upperBound)
        play()
    }

    func continueResting() {
        guard resting != nil else { return }
        enter(.playing)
    }

    private func enter(_ next: SpeedPlayback) {
        clock?.cancel()
        clock = nil
        mode = next
        guard next == .playing else {
            return
        }
        clock = Task { [weak self] in await self?.run() }
    }

    private func jump(to index: Int) {
        let playing = isPlaying
        pause()
        show(index)
        if playing {
            play()
        } else if mode == .stopped {
            enter(.paused)
        }
    }

    private func show(_ index: Int) {
        guard let text else { return }
        frame = text.frame(at: index, words: wordsPerFrame)
        markShown()
    }

    private func markShown() {
        guard !frame.isEmpty else {
            return
        }
        furthest = max(furthest ?? 0, frame.upperBound - 1)
    }

    private func run() async {
        while mode == .playing, let text {
            let seconds = text.duration(of: frame, wordsPerMinute: wordsPerMinute, pauses: pauseProfile)
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, mode == .playing else {
                return
            }
            guard !isAtEnd else {
                enter(.ended)
                return
            }
            let finished = frame
            show(frame.upperBound)
            if token?.isStop == true {
                enter(.stopped)
                return
            }
            guard let block = text.endedBlock(at: finished) else {
                continue
            }
            switch restMode {
            case .off:
                continue
            case .timed:
                mode = .resting(block)
                try? await Task.sleep(for: .seconds(restSeconds))
                guard !Task.isCancelled, case .resting = mode else {
                    return
                }
                mode = .playing
            case .manual:
                mode = .resting(block)
                return
            }
        }
    }
}

struct Press: Equatable {
    enum Phase: Equatable {
        case idle
        case down
        case holding
    }

    private(set) var phase = Phase.idle
    private var resumes = false

    var isHolding: Bool {
        phase == .holding
    }

    mutating func land() {
        guard phase == .idle else {
            return
        }
        phase = .down
    }

    mutating func hold(playing: Bool) -> Bool {
        guard phase == .down else {
            return false
        }
        phase = .holding
        resumes = playing
        return true
    }

    mutating func lift() -> Bool {
        let resume = phase == .holding && resumes
        phase = .idle
        resumes = false
        return resume
    }
}

struct SpeedReader: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    let reader: ReaderCoordinator
    let start: ReadingLine
    @State private var player = SpeedPlayer()
    @AppStorage private var wordsPerMinute: Int
    @AppStorage private var wordsPerFrame: Int
    @AppStorage private var pauseProfileJSON: String
    @AppStorage private var restModeRaw: String
    @AppStorage private var restSeconds: Double
    @AppStorage(ReaderAppearance.fontKey) private var font = ReaderFont.system
    @AppStorage(ReaderAppearance.backgroundKey) private var background = ReaderBackground.plain
    @State private var press = Press()
    @State private var holdTimer: Task<Void, Never>?
    @Namespace private var mediaZoom
    @State private var mediaPresenter = MediaPresenter()

    init(reader: ReaderCoordinator, start: ReadingLine) {
        self.reader = reader
        self.start = start
        let kind = reader.kind
        _wordsPerMinute = AppStorage(wrappedValue: 250, ReaderAppearance.SpeedSetting.wordsPerMinute.key(kind))
        _wordsPerFrame = AppStorage(wrappedValue: 1, ReaderAppearance.SpeedSetting.wordsPerFrame.key(kind))
        _pauseProfileJSON = AppStorage(wrappedValue: "", ReaderAppearance.SpeedSetting.pauses.key(kind))
        _restModeRaw = AppStorage(wrappedValue: SpeedRestMode.timed.rawValue, ReaderAppearance.SpeedSetting.restMode.key(kind))
        _restSeconds = AppStorage(wrappedValue: 1.6, ReaderAppearance.SpeedSetting.restSeconds.key(kind))
    }

    private static let speeds = 150...600

    var body: some View {
        VStack(spacing: 0) {
            bar
            progress
                .padding(.top, 12)
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.smooth(duration: 0.25), value: player.resting)
                .modifier(ReaderAppearanceModifier())
            controls
                .padding(.bottom, 8)
        }
        .padding(.horizontal, Tokens.gutter)
        .background(background.canvas)
        .environment(reader)
        .presentsMedia(mediaPresenter)
        .environment(\.mediaZoom, mediaZoom)
        .environment(\.mediaPresenter, mediaPresenter)
        .environment(\.openURL, OpenURLAction { url in
            guard url.isFileURL, ImageFiles.headerSize(of: url) != nil else {
                return .systemAction
            }
            mediaPresenter.open(url)
            return .handled
        })
        .task {
            player.wordsPerMinute = wordsPerMinute
            player.wordsPerFrame = wordsPerFrame
            player.pauseProfile = pauseProfile
            player.restMode = restMode
            player.restSeconds = restSeconds
            await player.load(reader.document, from: start)
        }
        .onChange(of: wordsPerMinute) { player.wordsPerMinute = wordsPerMinute }
        .onChange(of: wordsPerFrame) { player.wordsPerFrame = wordsPerFrame }
        .onChange(of: pauseProfileJSON) { player.pauseProfile = pauseProfile }
        .onChange(of: restModeRaw) { player.restMode = restMode }
        .onChange(of: restSeconds) { player.restSeconds = restSeconds }
        .onChange(of: scenePhase) {
            guard scenePhase != .active else { return }
            player.pause()
            saveShown()
            if scenePhase == .background {
                recordSummary()
            }
        }
        .onDisappear {
            player.pause()
            recordSummary()
        }
    }

    private var bar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                Button("Done") {
                    player.pause()
                    saveShown()
                    reader.send(.speedReading(false))
                }
                .buttonStyle(.glass)
                Spacer()
                Menu("Speed Reading Options", systemImage: "slider.horizontal.3") {
                    Menu("Pauses", systemImage: "pause.circle") {
                        ForEach(SpeedPauseKind.allCases, id: \.self) { kind in
                            Section(kind.name) {
                                Picker("Level", selection: Binding(
                                    get: { pauseProfile[kind] },
                                    set: { set($0, for: kind) }
                                )) {
                                    ForEach(SpeedPauseLevel.allCases, id: \.self) { level in
                                        Text(level.name).tag(level)
                                    }
                                }
                                Text(kind.detail)
                            }
                        }
                    }
                    Menu("Paragraph Preview", systemImage: "timer") {
                        Picker("After a Paragraph", selection: Binding(
                            get: { restMode },
                            set: { restModeRaw = $0.rawValue }
                        )) {
                            Text("Off").tag(SpeedRestMode.off)
                            Text("Timed").tag(SpeedRestMode.timed)
                            Text("Wait for Tap").tag(SpeedRestMode.manual)
                        }
                        .pickerStyle(.inline)
                        if restMode == .timed {
                            Stepper("Seconds: \(restSeconds, specifier: "%.1f")", value: $restSeconds, in: 1...10, step: 0.5)
                        }
                    }
                    ReaderAppearanceControls(showsColumn: false)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .padding(.top, 8)
    }

    private var pauseProfile: SpeedPauseProfile {
        SpeedPauseProfile(json: pauseProfileJSON)
    }

    private var restMode: SpeedRestMode {
        SpeedRestMode(rawValue: restModeRaw) ?? .timed
    }

    private func set(_ level: SpeedPauseLevel, for kind: SpeedPauseKind) {
        var next = pauseProfile
        next.set(level, for: kind)
        pauseProfileJSON = next.json
    }

    private var progress: some View {
        let token = player.token
        let blocks = max(reader.document.blocks.count, 1)
        let share = token.map { (Double($0.block) + $0.share) / Double(blocks) } ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text(sectionTitle(of: player.resting ?? player.previewed ?? token?.block ?? start.piece))
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            ReaderProgressBar(share: share)
        }
    }

    @ViewBuilder
    private var stage: some View {
        if let text = player.text {
            if let shown = player.resting ?? player.previewed {
                plate(shown)
                    .transition(.opacity)
            } else if let token = player.token {
                if token.isStop {
                    plate(token.block)
                        .padding(.vertical, Tokens.gap)
                } else {
                    words(in: text, token: token)
                        .overlay {
                            if press.isHolding {
                                plate(token.block)
                                    .background(ReaderBackgroundColor())
                                    .transition(.opacity)
                            }
                        }
                        .animation(.smooth(duration: 0.2), value: press.isHolding)
                }
            } else {
                Text("Nothing left to read.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Loading()
        }
    }

    private func words(in text: SpeedText, token: SpeedToken) -> some View {
        let frame = player.frame
        let shown = text.tokens[frame].map(\.text).joined(separator: " ")
        let before = frame.lowerBound > 0 ? text.tokens[frame.lowerBound - 1] : nil
        let after = frame.upperBound < text.tokens.count ? text.tokens[frame.upperBound] : nil
        let neighbor = { (other: SpeedToken?) in
            other.flatMap { $0.isStop || $0.block != token.block ? nil : $0.text } ?? ""
        }
        return PivotWord(text: shown, before: neighbor(before), after: neighbor(after))
            .font(font.font(.largeTitle))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(touch)
            .accessibilityElement()
            .accessibilityLabel(shown)
            .accessibilityHint("Tap to play or pause")
            .accessibilityAction { player.toggle() }
    }

    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard press.phase == .idle else {
                    if abs(value.translation.width) > 12 || abs(value.translation.height) > 12 {
                        holdTimer?.cancel()
                    }
                    return
                }
                press.land()
                holdTimer = Task {
                    try? await Task.sleep(for: .seconds(0.4))
                    guard !Task.isCancelled, press.hold(playing: player.isPlaying) else {
                        return
                    }
                    player.pause()
                }
            }
            .onEnded { value in
                holdTimer?.cancel()
                let wasHolding = press.isHolding
                let resume = press.lift()
                if wasHolding {
                    if resume {
                        player.play()
                    }
                    return
                }
                let dx = value.translation.width, dy = value.translation.height
                if abs(dx) > 50, abs(dx) > abs(dy) {
                    dx > 0 ? player.sentenceBack() : player.sentenceForward()
                } else if abs(dx) < 12, abs(dy) < 12 {
                    player.toggle()
                }
            }
    }

    private func plate(_ block: Int) -> some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    BlockView(
                        block: reader.document.blocks[block],
                        index: block,
                        baseURL: reader.baseURL,
                        mode: .reading,
                        readShare: 0,
                        markedReadThrough: false,
                        annotations: library.snapshot.annotations.filter { $0.materialID == reader.materialID && $0.piece == block },
                        fold: .none,
                        panGestures: false
                    )
                    .frame(maxWidth: Tokens.minReading)
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                transport("backward.fill", pagingPlates ? "Previous Plate" : "Previous Sentence") { player.stepBack() }
                Button(centerTitle, systemImage: player.isPlaying ? "pause.fill" : "play.fill") { player.toggle() }
                    .font(.largeTitle)
                    .frame(width: 84, height: 84)
                    .contentTransition(.symbolEffect(.replace))
                    .glassEffect(.regular.interactive(), in: Circle())
                    .disabled(player.token == nil || (player.token?.isStop == true && player.isAtEnd))
                transport("forward.fill", pagingPlates ? "Next Plate" : "Next Sentence") { player.stepForward() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            HStack {
                Button("Slower", systemImage: "minus") { wordsPerMinute = max(wordsPerMinute - 25, Self.speeds.lowerBound) }
                    .disabled(wordsPerMinute <= Self.speeds.lowerBound)
                Text("\(wordsPerMinute) wpm")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(wordsPerMinute)))
                    .frame(minWidth: 80)
                Button("Faster", systemImage: "plus") { wordsPerMinute = min(wordsPerMinute + 25, Self.speeds.upperBound) }
                    .disabled(wordsPerMinute >= Self.speeds.upperBound)
                Spacer()
                Picker("Words at Once", selection: $wordsPerFrame) {
                    Text("1 word").tag(1)
                    Text("2 words").tag(2)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .controlSize(.large)
            .animation(.snappy, value: wordsPerMinute)
        }
    }

    private func transport(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .font(.title2)
            .frame(width: 72, height: 72)
            .glassEffect(.regular.interactive(), in: Circle())
    }

    private var pagingPlates: Bool {
        player.previewed != nil || player.resting != nil || player.token?.isStop == true
    }

    private var centerTitle: String {
        if player.isPlaying {
            return "Pause"
        }
        return player.token?.isStop == true ? "Continue" : "Play"
    }

    private func sectionTitle(of block: Int) -> String {
        guard let heading = reader.document.heading(before: block), heading.index != reader.document.repeatedTitle else {
            return reader.title
        }
        return MarkedMarkdown.plainText(heading.title, baseURL: nil)
    }

    private func saveShown() {
        if let shown = player.shown { reader.send(.speedRead(shown)) }
    }

    private func recordSummary() {
        let summary = player.summary(itemID: reader.materialID, wordsPerMinute: wordsPerMinute, pauses: pauseProfile.json)
        guard summary.words > 0 else {
            return
        }
        Task { await library.recordReadingMode(summary) }
    }
}

struct ReaderProgressBar: View {
    let share: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.25))
                Capsule().fill(Color.accentColor)
                    .frame(width: geometry.size.width * min(max(share, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

private struct ReaderBackgroundColor: View {
    @AppStorage(ReaderAppearance.backgroundKey) private var background = ReaderBackground.plain

    var body: some View {
        background.canvas
    }
}

private struct PivotWord: View {
    let text: String
    let before: String
    let after: String

    var body: some View {
        PivotLayout {
            Text(Self.attributed(before: before, word: wordPrefix))
                .lineLimit(1)
                .minimumScaleFactor(0.15)
            Text(wordPivot)
                .lineLimit(1)
                .minimumScaleFactor(0.15)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
            Text(Self.attributed(suffix: wordSuffix, after: after))
                .lineLimit(1)
                .minimumScaleFactor(0.15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var characters: [Character] {
        Array(text)
    }

    private var pivot: Int {
        SpeedText.pivot(of: text)
    }

    private var wordPrefix: String {
        String(characters.prefix(pivot))
    }

    private var wordPivot: String {
        characters.indices.contains(pivot) ? String(characters[pivot]) : ""
    }

    private var wordSuffix: String {
        characters.indices.contains(pivot) ? String(characters.dropFirst(pivot + 1)) : ""
    }

    private static func attributed(before: String, word: String) -> AttributedString {
        var result = AttributedString()
        if !before.isEmpty {
            var dim = AttributedString(before + " ")
            dim.foregroundColor = Color(uiColor: .tertiaryLabel)
            result.append(dim)
        }
        result.append(AttributedString(word))
        return result
    }

    private static func attributed(suffix: String, after: String) -> AttributedString {
        var result = AttributedString(suffix)
        if !after.isEmpty {
            var dim = AttributedString(" " + after)
            dim.foregroundColor = Color(uiColor: .tertiaryLabel)
            result.append(dim)
        }
        return result
    }
}

private struct PivotLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = idealSize(of: subviews)
        return CGSize(width: proposal.width ?? ideal.width, height: proposal.height ?? ideal.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else {
            return
        }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let total = max(sizes.reduce(0) { $0 + $1.width }, 1)
        let scale = max(min(bounds.width / total, 1), 0.15)
        let scaled = sizes.map { CGSize(width: $0.width * scale, height: $0.height * scale) }
        let width = scaled.reduce(0) { $0 + $1.width }
        let lowest = bounds.minX
        let highest = bounds.maxX - width
        var x = min(max(bounds.midX - scaled[1].width / 2 - scaled[0].width, lowest), max(highest, lowest))
        for (index, subview) in subviews.enumerated() {
            let size = scaled[index]
            subview.place(
                at: CGPoint(x: x, y: bounds.midY - size.height / 2),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width
        }
    }

    private func idealSize(of subviews: Subviews) -> CGSize {
        var size = CGSize.zero
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            size.width += ideal.width
            size.height = max(size.height, ideal.height)
        }
        return size
    }
}
