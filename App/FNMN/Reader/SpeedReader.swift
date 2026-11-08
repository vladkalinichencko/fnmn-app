import FNMNCore
import SwiftUI

/// How much longer long words, numbers and punctuation stay on screen while speed reading.
enum SpeedPauses: String, CaseIterable, Identifiable {
    case off, slight, regular
    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: "Off"
        case .slight: "Slight"
        case .regular: "Regular"
        }
    }

    /// The share of each token's extra beats that is waited out.
    var share: Double {
        switch self {
        case .off: 0
        case .slight: 0.5
        case .regular: 1
        }
    }
}

/// What speed reading is doing: the text is still being split, the words wait, they run, they rest on a block shown
/// whole, or the text is at its end.
enum SpeedPlayback: Equatable {
    case loading
    case paused
    case playing
    case stopped
    case ended
}

/// The clock of speed reading: which tokens are on screen, whether they run on by themselves, and how far the text
/// has been shown. What was shown becomes read only when the reader sends it to the coordinator.
@MainActor @Observable
final class SpeedPlayer {
    private(set) var text: SpeedText?
    /// The tokens on screen.
    private(set) var frame = 0..<0
    /// Playing is the only mode with a clock; `enter` starts and cancels it.
    private(set) var mode = SpeedPlayback.loading
    /// The last token shown so far. Going back a sentence leaves it where it is, so rereading takes nothing read away.
    private(set) var furthest: Int?
    var wordsPerMinute = 250
    var pauses = 1.0
    var wordsPerFrame = 1 {
        didSet {
            // A paused frame takes the new size at once; a running one at the next step.
            if mode != .playing, let text {
                frame = text.frame(at: frame.lowerBound, words: wordsPerFrame)
            }
        }
    }
    @ObservationIgnored private var clock: Task<Void, Never>?

    var isPlaying: Bool {
        mode == .playing
    }

    /// The clock runs only while the words do; a waiting, stopped or finished player keeps none.
    var hasClock: Bool {
        clock != nil
    }

    /// The text is split into tokens off the main thread: a book is hundreds of thousands of words.
    func load(_ document: ReaderDocument, from start: ReadingLine) async {
        guard text == nil else { return }
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

    /// The block of the last token shown and the share of that block's tokens shown up to it.
    var shown: ReadingLine? {
        guard let text, let furthest else { return nil }
        return ReadingLine(piece: text.tokens[furthest].block, fraction: text.tokens[furthest].share)
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    /// Words run on from the frame on screen. A block shown whole waits for Continue.
    func play() {
        guard mode != .playing, let token, !token.isStop else {
            return
        }
        markShown()
        enter(.playing)
    }

    func pause() {
        guard mode == .playing else {
            return
        }
        enter(.paused)
    }

    func sentenceBack() {
        guard let text else {
            return
        }
        jump(to: text.sentenceStart(before: frame.lowerBound))
    }

    func sentenceForward() {
        guard let next = text?.sentenceStart(after: frame.lowerBound) else { return }
        jump(to: next)
    }

    /// From a block shown whole on to the words after it, running again.
    func continuePastStop() {
        guard !isAtEnd else { return }
        show(frame.upperBound)
        play()
    }

    /// The one writer of the mode; the clock exists exactly while the words run.
    private func enter(_ next: SpeedPlayback) {
        mode = next
        guard next == .playing else {
            clock?.cancel()
            clock = nil
            return
        }
        clock = Task { [weak self] in await self?.run() }
    }

    private func jump(to index: Int) {
        let playing = isPlaying
        pause()
        show(index)
        if playing { play() }
    }

    private func show(_ index: Int) {
        guard let text else { return }
        frame = text.frame(at: index, words: wordsPerFrame)
        markShown()
    }

    private func markShown() {
        guard !frame.isEmpty else { return }
        furthest = max(furthest ?? 0, frame.upperBound - 1)
    }

    /// Each frame stays for its own time, read at every step so a new speed takes effect on the next word.
    private func run() async {
        while isPlaying, let text {
            let seconds = text.duration(of: frame, wordsPerMinute: wordsPerMinute, pauses: pauses)
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, isPlaying else { return }
            guard !isAtEnd else {
                enter(.ended)
                return
            }
            show(frame.upperBound)
            if token?.isStop == true {
                enter(.stopped)
                return
            }
        }
    }
}

/// One finger on the words: a press that rests long enough shows the whole block and the words wait, and only that
/// press starts them again when it lifts. Anything else the finger does leaves the press at rest.
struct Press: Equatable {
    enum Phase: Equatable {
        case idle
        /// A finger is down and the words still run.
        case down
        /// The finger rested: the block shows whole and the words wait.
        case holding
    }

    private(set) var phase = Phase.idle
    private var resumes = false

    var isHolding: Bool {
        phase == .holding
    }

    /// A finger landed; one that is already down changes nothing.
    mutating func land() {
        guard phase == .idle else {
            return
        }
        phase = .down
    }

    /// The rest is over. Returns whether it took effect, since the finger may have lifted first.
    mutating func hold(playing: Bool) -> Bool {
        guard phase == .down else {
            return false
        }
        phase = .holding
        resumes = playing
        return true
    }

    /// The finger lifted. Returns whether the words run on, and leaves the press ready for the next one.
    mutating func lift() -> Bool {
        let resume = phase == .holding && resumes
        phase = .idle
        resumes = false
        return resume
    }
}

/// Speed reading over the whole screen: the words one or two at a time at one point, the letter to rest the eye on in
/// red and set under a mark, the words around them faint. It covers the reader instead of lying over the column, since
/// nothing of the page should draw the eye away, and it leaves only through Done, which hands what was shown to the
/// reader as read.
struct SpeedReader: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    let reader: ReaderCoordinator
    let start: ReadingLine
    @State private var player = SpeedPlayer()
    @AppStorage(ReaderAppearance.speedKey) private var wordsPerMinute = 250
    @AppStorage(ReaderAppearance.speedWordsKey) private var wordsPerFrame = 1
    @AppStorage(ReaderAppearance.speedPausesKey) private var pauses = SpeedPauses.regular
    @AppStorage(ReaderAppearance.fontKey) private var font = ReaderFont.system
    /// The current block shows whole while a finger rests on the words.
    @State private var press = Press()
    @State private var holdTimer: Task<Void, Never>?

    private static let speeds = 150...600
    /// Above this speed, studies find less of the text understood.
    private static let comfortable = 300

    var body: some View {
        VStack(spacing: 0) {
            bar
            progress
                .padding(.top, 12)
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
                .padding(.bottom, 8)
        }
        .padding(.horizontal, Tokens.gutter)
        .modifier(ReaderAppearanceModifier())
        .environment(reader)
        .task {
            player.wordsPerMinute = wordsPerMinute
            player.wordsPerFrame = wordsPerFrame
            player.pauses = pauses.share
            await player.load(reader.document, from: start)
        }
        .onChange(of: wordsPerMinute) { player.wordsPerMinute = wordsPerMinute }
        .onChange(of: wordsPerFrame) { player.wordsPerFrame = wordsPerFrame }
        .onChange(of: pauses) { player.pauses = pauses.share }
        // A locked screen or another app stops the words, and what was shown is saved in case the app is closed.
        .onChange(of: scenePhase) {
            guard scenePhase != .active else { return }
            player.pause()
            saveShown()
        }
        .onDisappear { player.pause() }
    }

    private var bar: some View {
        HStack {
            Button("Done") {
                player.pause()
                saveShown()
                reader.send(.speedReading(false))
            }
            .buttonStyle(.glass)
            Spacer()
            Menu("Speed Reading Options", systemImage: "slider.horizontal.3") {
                Picker(selection: $pauses) {
                    ForEach(SpeedPauses.allCases) { Text($0.name).tag($0) }
                } label: {
                    Label("Pauses", systemImage: "pause.circle")
                    Text(pauses.name)
                }
                .pickerStyle(.menu)
                ReaderAppearanceControls()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
        }
        .padding(.top, 8)
    }

    /// The section being read, how much of the material lies behind and how long the rest takes at this speed.
    private var progress: some View {
        let token = player.token
        let blocks = max(reader.document.blocks.count, 1)
        let share = token.map { (Double($0.block) + $0.share) / Double(blocks) } ?? 0
        let minutes = player.text?.minutesLeft(from: player.frame.lowerBound, wordsPerMinute: wordsPerMinute, pauses: pauses.share) ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text(sectionTitle(of: token?.block ?? start.piece))
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.25))
                    Capsule().fill(Color.accentColor)
                        .frame(width: geometry.size.width * min(max(share, 0), 1))
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
            if let token = player.token {
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

    /// The frame on its fixed point, the word before it and the word after it faint on either side.
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

    /// One finger does all on the words: a tap plays or pauses, a swipe to the right goes back a sentence and one to
    /// the left on a sentence, and resting the finger shows the whole block until it lifts.
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

    /// A block as the column draws it, for what cannot be read a word at a time and for a look at the whole paragraph.
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

    /// The heading of the section a block stands in, or the material's title before the first one.
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

/// The page color of the reader's chosen background, behind a block shown over the words.
private struct ReaderBackgroundColor: View {
    @AppStorage(ReaderAppearance.backgroundKey) private var background = ReaderBackground.plain

    var body: some View {
        background.canvas
    }
}

/// Words set so the letter to rest the eye on stands at the same point whatever the word: the point lies a little left
/// of the middle, where a word's recognition point falls, and two short marks above and below it show it apart from
/// the color.
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
    /// The point the eye rests on, a little left of the middle of the line.
    private enum Pivot: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context.width * 0.42 }
    }

    fileprivate static let pivot = HorizontalAlignment(Pivot.self)
}
