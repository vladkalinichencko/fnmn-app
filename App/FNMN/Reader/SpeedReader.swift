import FNMNCore
import SwiftUI

enum SpeedPlayback: Equatable {
    case loading
    case paused
    case playing
    case resting(Int)
    case stopped
    case ended
}

@MainActor @Observable
final class SpeedPlayer {
    private(set) var text: SpeedText?
    private(set) var frame = 0..<0
    private(set) var mode = SpeedPlayback.loading
    private(set) var furthest: Int?
    var wordsPerMinute = 250
    var pauseProfile = SpeedPauseProfile()
    var wordsPerFrame = 1 {
        didSet {
            if mode != .playing, let text {
                frame = text.frame(at: frame.lowerBound, words: wordsPerFrame)
            }
        }
    }
    @ObservationIgnored private var clock: Task<Void, Never>?
    private(set) var backs = 0
    @ObservationIgnored private var startedAt = Date.now

    var isPlaying: Bool {
        mode == .playing
    }

    var resting: Int? {
        if case let .resting(block) = mode {
            return block
        }
        return nil
    }

    func load(_ document: ReaderDocument, from start: ReadingLine) async {
        guard text == nil else { return }
        startedAt = .now
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
        isPlaying ? pause() : play()
    }

    func play() {
        guard mode != .playing, let token, !token.isStop else {
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
        ReadingModeEvent(
            itemID: itemID,
            mode: .rsvp,
            wordsPerMinute: wordsPerMinute,
            pauses: pauses,
            words: (furthest ?? -1) + 1,
            backs: backs,
            startedAt: startedAt,
            endedAt: .now
        )
    }

    func sentenceForward() {
        guard let next = text?.sentenceStart(after: frame.lowerBound) else { return }
        jump(to: next)
    }

    func continuePastStop() {
        guard !isAtEnd else { return }
        show(frame.upperBound)
        play()
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
            mode = .resting(block)
            try? await Task.sleep(for: .seconds(Self.restSeconds))
            guard !Task.isCancelled, case .resting = mode else {
                return
            }
            mode = .playing
        }
    }

    private static let restSeconds: Double = 1.6
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
    @AppStorage(ReaderAppearance.fontKey) private var font = ReaderFont.system
    @State private var press = Press()
    @State private var holdTimer: Task<Void, Never>?

    init(reader: ReaderCoordinator, start: ReadingLine) {
        self.reader = reader
        self.start = start
        let kind = reader.kind
        _wordsPerMinute = AppStorage(wrappedValue: 250, ReaderAppearance.SpeedSetting.wordsPerMinute.key(kind))
        _wordsPerFrame = AppStorage(wrappedValue: 1, ReaderAppearance.SpeedSetting.wordsPerFrame.key(kind))
        _pauseProfileJSON = AppStorage(wrappedValue: "", ReaderAppearance.SpeedSetting.pauses.key(kind))
    }

    private static let speeds = 150...600
    private static let comfortable = 300

    var body: some View {
        VStack(spacing: 0) {
            bar
            progress
                .padding(.top, 12)
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.smooth(duration: 0.25), value: player.resting)
            controls
                .padding(.bottom, 8)
        }
        .padding(.horizontal, Tokens.gutter)
        .modifier(ReaderAppearanceModifier())
        .environment(reader)
        .task {
            player.wordsPerMinute = wordsPerMinute
            player.wordsPerFrame = wordsPerFrame
            player.pauseProfile = pauseProfile
            await player.load(reader.document, from: start)
        }
        .onChange(of: wordsPerMinute) { player.wordsPerMinute = wordsPerMinute }
        .onChange(of: wordsPerFrame) { player.wordsPerFrame = wordsPerFrame }
        .onChange(of: pauseProfileJSON) { player.pauseProfile = pauseProfile }
        .onChange(of: scenePhase) {
            guard scenePhase != .active else { return }
            player.pause()
            saveShown()
        }
        .onDisappear {
            player.pause()
            let summary = player.summary(itemID: reader.materialID, wordsPerMinute: wordsPerMinute, pauses: pauseProfile.json)
            guard summary.words > 0 else {
                return
            }
            Task { await library.recordReadingMode(summary) }
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
                            Picker(kind.name, selection: Binding(
                                get: { pauseProfile[kind] },
                                set: { set($0, for: kind) }
                            )) {
                                ForEach(SpeedPauseLevel.allCases, id: \.self) { level in
                                    Text(level.name).tag(level)
                                }
                            }
                            .pickerStyle(.inline)
                        }
                    }
                    ReaderAppearanceControls()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
            }
        }
        .padding(.top, 8)
    }

    private var pauseProfile: SpeedPauseProfile {
        SpeedPauseProfile(json: pauseProfileJSON)
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
        let minutes = player.text?.minutesLeft(from: player.frame.lowerBound, wordsPerMinute: wordsPerMinute, pauses: pauseProfile) ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text(sectionTitle(of: token?.block ?? start.piece))
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { _ in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.25))
                    Capsule().fill(Color.accentColor)
                        .scaleEffect(x: min(max(share, 0), 1), anchor: .leading)
                }
            }
            .frame(height: 3)
            Text("\(Int((share * 100).rounded()))% · \(Int(minutes.rounded(.up))) min left")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stage: some View {
        if let text = player.text {
            if let resting = player.resting {
                plate(resting)
                    .transition(.opacity)
            } else if let token = player.token {
                if token.isStop {
                    VStack(spacing: Tokens.gap) {
                        plate(token.block)
                        Button("Continue") { player.continuePastStop() }
                            .buttonStyle(.glassProminent)
                            .disabled(player.isAtEnd)
                    }
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
        ScrollView {
            BlockView(
                block: reader.document.blocks[block],
                index: block,
                baseURL: reader.baseURL,
                mode: .reading,
                readShare: 0,
                markedReadThrough: false,
                annotations: library.snapshot.annotations.filter { $0.materialID == reader.materialID && $0.piece == block },
                fold: .none
            )
            .frame(maxWidth: Tokens.minReading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 36) {
                Button("Previous Sentence", systemImage: "backward.fill") { player.sentenceBack() }
                    .font(.title2)
                Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") { player.toggle() }
                    .font(.largeTitle)
                    .frame(width: 84, height: 84)
                    .contentTransition(.symbolEffect(.replace))
                    .glassEffect(.regular.interactive(), in: Circle())
                    .disabled(player.token?.isStop ?? true)
                Button("Next Sentence", systemImage: "forward.fill") { player.sentenceForward() }
                    .font(.title2)
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
            .animation(.snappy, value: wordsPerMinute)
            if wordsPerMinute > Self.comfortable {
                Text("Above \(Self.comfortable) words a minute, less of the text is understood.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
        let characters = Array(text)
        let pivot = SpeedText.pivot(of: text)
        let head = String(characters.prefix(pivot))
        let letter = characters.indices.contains(pivot) ? String(characters[pivot]) : ""
        let tail = String(characters.dropFirst(pivot + 1))
        VStack(alignment: .pivot, spacing: 6) {
            Self.mark
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(before.isEmpty ? "" : before + " ").foregroundStyle(.tertiary)
                Text(head)
                Text(letter)
                    .bold()
                    .foregroundStyle(Self.red)
                    .alignmentGuide(.pivot) { $0[HorizontalAlignment.center] }
                Text(tail)
                Text(after.isEmpty ? "" : " " + after).foregroundStyle(.tertiary)
            }
            .lineLimit(1)
            .fixedSize()
            Self.mark
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: .pivot, vertical: .center))
        .clipped()
    }

    private static let red = Color(red: 0.9, green: 0.12, blue: 0.16)

    private static var mark: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 2, height: 12)
            .alignmentGuide(.pivot) { $0[HorizontalAlignment.center] }
    }
}

extension HorizontalAlignment {
    private enum Pivot: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context.width * 0.42 }
    }

    fileprivate static let pivot = HorizontalAlignment(Pivot.self)
}
