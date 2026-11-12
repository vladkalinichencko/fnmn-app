import FNMNCore
import SwiftUI

enum Column: Equatable {
    case laidOut
    case jumping(to: Int, hiding: Bool)
}

enum FindResult: Equatable {
    case idle
    case searching
    case matches([TextMatch], current: Int)
}

struct FindState: Equatable {
    var query = ""
    var result = FindResult.idle

    var matches: [TextMatch] {
        if case let .matches(matches, _) = result {
            return matches
        }
        return []
    }

    var current: Int? {
        if case let .matches(matches, current) = result, matches.indices.contains(current) {
            return current
        }
        return nil
    }
}

struct SpotState: Equatable {
    var piece: Int
    var word: Int
    var span: TextSpan
    var running: Bool
    var words = 0
    var startedAt = Date.now
}

struct SpotWord: Equatable {
    let span: TextSpan
    let token: SpeedToken
}

struct SpotPiece: Equatable {
    let piece: Int
    let words: [SpotWord]
}

struct ReaderState: Equatable {
    var mode = PlateMode.reading
    var folded: Set<Int> = []
    var place: Int?
    var scrollID: Int?
    var column = Column.laidOut
    var keepsPlace = false
    var opening: Int? {
        if case let .jumping(to, _) = column {
            return to
        }
        return nil
    }

    var hidesColumn: Bool {
        if case .jumping(_, hiding: true) = column {
            return true
        }
        return false
    }
    var showsLine = false
    var line: ReadingLine?
    var shownPlate: Int?
    var speedStart: ReadingLine?
    var find: FindState?
    var spot: SpotState?
}

enum ReaderAction {
    case opened
    case scrolled(Int)
    case plate(PlateAction)
    case toggleSection(Int)
    case foldAll(Bool)
    case mark(AnnotationCommand, AnnotationTarget)
    case note(String, AnnotationTarget)
    case readThrough(Int?)
    case showLine(Bool)
    case moveLine(ReadingLine)
    case settleLine
    case ask(String)
    case copyPrompt(String)
    case onePlate(Bool)
    case turnPlate(forward: Bool)
    case speedReading(Bool)
    case speedRead(ReadingLine)
    case find(Bool)
    case findQuery(String)
    case findStep(Int)
    case found([TextMatch], query: String)
    case spot(Bool)
    case spotPaused(Bool)
    case spotMove(SpotState)
}

func readerReduce(_ state: ReaderState, _ action: ReaderAction, document: ReaderDocument) -> ReaderState {
    var state = state
    switch action {
    case .opened:
        guard case let .jumping(to, _) = state.column else {
            return state
        }
        state.column = .laidOut
        state.scrollID = to
    case let .scrolled(index):
        guard state.column == .laidOut else {
            return state
        }
        state.scrollID = index
        if document.blocks.indices.contains(index), !state.keepsPlace, state.shownPlate == nil {
            state.place = index
        }
    case let .plate(action):
        state.mode = plateReduce(state.mode, action)
    case let .toggleSection(index):
        guard document.holdsBlocks(index) else { return state }
        if state.folded.remove(index) == nil { state.folded.insert(index) }
    case let .foldAll(closed):
        state.folded = closed ? document.lowestHeadings : []
    case let .readThrough(piece):
        guard state.showsLine, let line = state.line else { return state }
        let blocks = state.shownPlate == nil ? document.visibleBlocks(folded: state.folded) : document.plates
        let block = if let piece { blocks.first { $0 > piece } } else { blocks.last { $0 < line.piece } }
        if let block { state.line = ReadingLine(piece: block, fraction: 0) }
    case let .showLine(shows):
        state.showsLine = shows
        if shows, let piece = state.place ?? document.visibleBlocks(folded: state.folded).first,
           state.line.map({ $0.piece < piece }) ?? true {
            state.line = ReadingLine(piece: piece, fraction: 0)
        }
    case let .moveLine(line):
        state.line = line
    case .onePlate(true):
        guard state.shownPlate == nil else { return state }
        let start: Int? = if state.showsLine, let line = state.line {
            line.fraction >= 1 ? document.plate(after: line.piece) ?? line.piece : line.piece
        } else {
            state.scrollID ?? state.place
        }
        state.shownPlate = document.plate(holding: start ?? 0)
        state.mode = .reading
    case .onePlate(false):
        guard let plate = state.shownPlate else { return state }
        state.shownPlate = nil
        state.mode = .reading
        if !state.keepsPlace { state.place = plate }
        state.folded.subtract(document.headings(holding: plate))
        state.column = .jumping(to: plate, hiding: false)
    case let .turnPlate(forward):
        guard state.mode == .reading, let plate = state.shownPlate,
              let next = forward ? document.plate(after: plate) : document.plate(before: plate) else { return state }
        state.shownPlate = next
        state.keepsPlace = false
        state.place = next
        if state.showsLine { state.line = ReadingLine(piece: next, fraction: 0) }
    case .speedReading(true):
        guard state.speedStart == nil else { return state }
        state.speedStart = if state.showsLine, let line = state.line {
            line
        } else {
            ReadingLine(piece: state.shownPlate ?? state.scrollID ?? state.place ?? 0, fraction: 0)
        }
        state.mode = .reading
    case .speedReading(false):
        state.speedStart = nil
    case let .speedRead(shown):
        guard state.speedStart != nil else { return state }
        let next = shown.fraction >= 1 ? document.plate(after: shown.piece) : nil
        let line = next.map { ReadingLine(piece: $0, fraction: 0) } ?? shown
        state.keepsPlace = false
        state.place = line.piece
        if state.showsLine { state.line = line }
        if state.shownPlate != nil {
            state.shownPlate = document.plate(holding: line.piece)
        } else {
            state.folded.subtract(document.headings(holding: line.piece))
            state.column = .jumping(to: line.piece, hiding: false)
        }
    case .mark, .note, .settleLine, .ask, .copyPrompt:
        break
    case .find(true):
        state.find = FindState()
    case .find(false):
        state.find = nil
    case let .findQuery(query):
        guard state.find != nil else {
            return state
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        state.find = FindState(query: query, result: needle.isEmpty ? .idle : .searching)
    case let .findStep(step):
        guard case let .matches(matches, current)? = state.find?.result, !matches.isEmpty else {
            return state
        }
        state.find?.result = .matches(matches, current: (current + step + matches.count) % matches.count)
    case let .found(matches, query):
        guard state.find?.query == query else {
            return state
        }
        state.find?.result = .matches(matches, current: 0)
    case .spot(true):
        guard state.spot == nil else {
            return state
        }
        let around = state.place ?? state.scrollID ?? document.visibleBlocks(folded: state.folded).first ?? 0
        guard let start = document.plate(holding: around) else {
            return state
        }
        state.spot = SpotState(piece: start, word: 0, span: TextSpan(start: 0, length: 0), running: true)
    case .spot(false):
        state.spot = nil
    case let .spotPaused(paused):
        state.spot?.running = !paused
    case var .spotMove(next):
        next.words = (state.spot?.words ?? 0) + 1
        next.startedAt = state.spot?.startedAt ?? .now
        state.spot = next.running ? next : SpotState(piece: next.piece, word: next.word, span: next.span, running: false, words: next.words, startedAt: next.startedAt)
    }
    return state
}

@MainActor @Observable
final class ReaderCoordinator {
    let document: ReaderDocument
    let materialID: String
    let title: String
    let source: SourceRef?
    let baseURL: URL
    let kind: FNMNCore.Material.Kind
    private(set) var state: ReaderState
    @ObservationIgnored var scroll: (Int) -> Void = { _ in }
    @ObservationIgnored private(set) var revealed: Set<Int> = []
    private(set) var rows: [Int: CGRect] = [:]
    private(set) var shown: Set<Int> = []
    private var textLines: [ClosedRange<Double>] = []
    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private var texts: [Int: String]?
    @ObservationIgnored private let plainText: @Sendable (String) -> String
    @ObservationIgnored private var spotClock: Task<Void, Never>?
    @ObservationIgnored private var spotPieces: [Int: SpotPiece] = [:]

    init(document: ReaderDocument, materialID: String, title: String, source: SourceRef?, baseURL: URL, kind: FNMNCore.Material.Kind, place: Int?, note: Int?, showsLine: Bool, onePlate: Bool, library: LibraryModel, plainText: @escaping @Sendable (String) -> String) {
        self.document = document
        self.materialID = materialID
        self.title = title
        self.source = source
        self.baseURL = baseURL
        self.kind = kind
        self.plainText = plainText
        state = ReaderState(place: place, keepsPlace: note != nil)
        self.library = library
        let saved = library.progress.folded[materialID].map(Set.init) ?? document.lowestHeadings
        state.folded = (note ?? place).map {
            saved.subtracting(document.headings(holding: $0)).union(document.headings(endingAbove: $0))
        } ?? saved
        if let target = (note ?? place).flatMap({ readingPlaceTarget(place: $0, visible: visible) }) {
            state.column = .jumping(to: target, hiding: true)
        }
        state.line = library.progress.lines[materialID]
        if note == nil, place != nil, state.line?.piece != place { state.line = nil }
        state = readerReduce(state, .showLine(showsLine), document: document)
        if onePlate {
            state = readerReduce(state, .onePlate(true), document: document)
            if let note { state.shownPlate = document.plate(holding: note) }
        }
    }

    func send(_ action: ReaderAction) {
        let before = state
        let next = readerReduce(state, action, document: document)
        revealed = next.folded == before.folded ? [] : Set(document.visibleBlocks(folded: next.folded)).subtracting(visible)
        if next != before { withAnimation(animation(for: action)) { state = next } }
        perform(action, from: before, to: next)
    }

    var visible: [Int] { document.visibleBlocks(folded: state.folded) }

    var passedHeading: (index: Int, title: String)? {
        (state.shownPlate ?? state.scrollID).flatMap { document.heading(before: $0) }.flatMap { $0.index == document.repeatedTitle ? nil : $0 }
    }

    func current(in visible: [Int]) -> Int? {
        readingPlaceTarget(place: state.place, visible: visible)
    }

    func target(_ piece: Int, text: String, quote: String? = nil) -> AnnotationTarget {
        let span = quote.flatMap { quote -> TextSpan? in
            let found = (text as NSString).range(of: quote)
            return found.location == NSNotFound ? nil : TextSpan(start: found.location, length: found.length)
        }
        return AnnotationTarget(materialID: materialID, piece: piece, text: text, span: span)
    }

    func y(of line: ReadingLine) -> CGFloat? {
        let visible = visible
        guard visible.contains(line.piece) else {
            return visible.last { $0 < line.piece }.flatMap { shown.contains($0) ? rows[$0] : nil }.map { $0.maxY - Tokens.gap / 2 }
        }
        guard let block = stops(of: line.piece) else { return nil }
        guard line.fraction > 0 else { return CGFloat(block.top) }
        guard line.fraction < 1 else { return block.row.maxY - Tokens.gap / 2 }
        let y = Double(block.row.minY + line.fraction * (block.row.height - Tokens.gap))
        return CGFloat(ReadingLine.nearest(to: y, in: block.inside) ?? y)
    }

    func line(near y: CGFloat) -> ReadingLine? {
        let y = Double(y)
        var nearest: (line: ReadingLine, distance: Double)?
        for block in visible.compactMap(stops(of:)) {
            let height = max(Double(block.row.height - Tokens.gap), 1)
            let inside = block.inside.map { stop in
                let place = min(max(y, stop.lowerBound), stop.upperBound)
                return (place, min((place - Double(block.row.minY)) / height, 1))
            }
            for (place, fraction) in [(block.top, 0)] + inside where abs(place - y) < nearest?.distance ?? .infinity {
                nearest = (ReadingLine(piece: block.piece, fraction: fraction), abs(place - y))
            }
        }
        return nearest?.line
    }

    func stop(of line: ReadingLine) -> Int? {
        guard let y = y(of: line).map(Double.init) else { return nil }
        let stops = visible.compactMap(stops(of:)).flatMap { [$0.top...$0.top] + $0.inside }
        let distance = { (stop: ClosedRange<Double>) in abs(min(max(y, stop.lowerBound), stop.upperBound) - y) }
        return stops.indices.min { distance(stops[$0]) < distance(stops[$1]) }
    }

    private func stops(of piece: Int) -> BlockStops? {
        guard shown.contains(piece), let row = rows[piece] else { return nil }
        let content = Double(row.minY)...Double(row.maxY - Tokens.gap)
        let lines = textLines.filter { content.contains(($0.lowerBound + $0.upperBound) / 2) }
        let isText = switch document.blocks[piece] {
        case .heading, .text: true
        case .image, .video, .interactive: false
        }
        let start = if case .heading = document.blocks[piece], let first = lines.first { first.lowerBound } else { content.lowerBound }
        let inside = isText && lines.isEmpty ? [] : ReadingLine.stops(within: content, lines: lines)
        let end = Double(row.maxY - Tokens.gap / 2)
        return BlockStops(
            piece: piece,
            row: row,
            top: (content.lowerBound - Double(Tokens.gap) + start) / 2,
            inside: piece == visible.last ? inside + [end...end] : inside
        )
    }

    private struct BlockStops {
        let piece: Int
        let row: CGRect
        let top: Double
        let inside: [ClosedRange<Double>]
    }

    func rowChanged(_ index: Int, _ row: CGRect) {
        rows[index] = row
    }

    func shownChanged(_ blocks: [Int]) {
        let blocks = Set(blocks)
        if blocks != shown { shown = blocks }
    }

    func textLinesChanged(_ lines: [ClosedRange<CGFloat>]) {
        let merged = ReadingLine.merged(lines.map { Double($0.lowerBound)...Double($0.upperBound) })
        if merged != textLines { textLines = merged }
    }

    private func animation(for action: ReaderAction) -> Animation? {
        switch action {
        case .plate: .snappy
        case .toggleSection, .foldAll, .opened, .scrolled, .mark, .note, .readThrough, .showLine, .moveLine, .settleLine, .ask, .copyPrompt, .onePlate, .turnPlate, .speedReading, .speedRead, .find, .findQuery, .findStep, .found, .spot, .spotPaused, .spotMove: nil
        }
    }

    private func perform(_ action: ReaderAction, from before: ReaderState, to next: ReaderState) {
        switch action {
        case .scrolled:
            guard let place = next.place, place != before.place else { return }
            savePlace(place)
        case let .mark(command, target):
            let change: LibraryChange = switch command {
            case let .mark(mark): .mark(mark, target)
            case let .unmark(mark): .unmark(mark, target)
            }
            Task { await library.apply(change) }
        case let .note(text, target):
            Task { await library.apply(.note(text, target)) }
        case let .readThrough(piece):
            if next.showsLine {
                guard next.line != before.line else { return }
                library.apply(.line(next.line, itemID: materialID))
            } else {
                library.apply(.readThrough(piece: piece, itemID: materialID))
            }
            savePlace(next.place)
        case .showLine:
            if next.line != before.line { library.apply(.line(next.line, itemID: materialID)) }
            savePlace(next.place)
        case .moveLine:
            break
        case .settleLine:
            guard next.line != library.progress.lines[materialID] else { return }
            library.apply(.line(next.line, itemID: materialID))
            savePlace(next.place)
        case let .ask(passage):
            ChatGPTHandoff.copyAndOpen(title: title, passage: passage)
        case let .copyPrompt(passage):
            _ = ChatGPTHandoff.remember(title: title, passage: passage)
        case .opened:
            guard next != before, let target = next.scrollID else { return }
            scroll(target)
        case .plate:
            break
        case .toggleSection, .foldAll:
            guard next.folded != before.folded else { return }
            library.apply(.fold(next.folded.sorted(), itemID: materialID))
            if let place = next.place, !visible.contains(place), let target = current(in: visible) {
                scroll(target)
            }
        case .onePlate:
            ReaderAppearance.setReadsOnePlate(next.shownPlate != nil, materialID: materialID)
            if next.folded != before.folded { library.apply(.fold(next.folded.sorted(), itemID: materialID)) }
            if next.place != before.place { savePlace(next.place) }
            if next.opening != nil, before.opening == nil {
                Task {
                    await Task.yield()
                    self.send(.opened)
                }
            }
        case .turnPlate:
            guard next.shownPlate != before.shownPlate else { return }
            if next.line != before.line { library.apply(.line(next.line, itemID: materialID)) }
            savePlace(next.place)
        case .speedReading:
            break
        case let .findQuery(query):
            guard next.find?.result == .searching else {
                return
            }
            search(query)
        case .findStep, .found:
            guard let find = next.find, let current = find.current else {
                return
            }
            scroll(find.matches[current].piece)
        case .spot(true):
            startSpot()
        case .spot(false):
            stopSpot()
            if let spot = before.spot {
                let defaults = UserDefaults.standard
                let event = ReadingModeEvent(
                    itemID: materialID,
                    mode: .spot,
                    wordsPerMinute: defaults.integer(forKey: ReaderAppearance.SpeedSetting.wordsPerMinute.key(kind)),
                    pauses: defaults.string(forKey: ReaderAppearance.SpeedSetting.pauses.key(kind)) ?? "",
                    words: spot.words,
                    backs: 0,
                    startedAt: spot.startedAt,
                    endedAt: .now
                )
                Task { await library.recordReadingMode(event) }
            }
            savePlace(next.place)
        case let .spotPaused(paused):
            if paused {
                spotClock?.cancel()
                spotClock = nil
            } else {
                scheduleSpot()
            }
        case let .spotMove(next):
            if let before = before.spot, before.piece != next.piece {
                scroll(next.piece)
                savePlace(next.piece)
            }
            scheduleSpot()
        case .find:
            break
        case .speedRead:
            guard next != before else { return }
            if next.line != before.line { library.apply(.line(next.line, itemID: materialID)) }
            if next.folded != before.folded { library.apply(.fold(next.folded.sorted(), itemID: materialID)) }
            savePlace(next.place)
            if next.opening != nil {
                Task {
                    await Task.yield()
                    self.send(.opened)
                }
            }
        }
    }

    private func savePlace(_ place: Int?) {
        let lineRead = state.line.map { $0.fraction >= 1 ? $0.piece : $0.piece - 1 }
        let read = if state.showsLine, let lineRead {
            lineRead
        } else {
            [place, library.progress.readThrough[materialID], lineRead].compactMap { $0 }.max() ?? -1
        }
        let position = place.map(ReadingPosition.piece) ?? library.position(of: materialID) ?? .piece(0)
        library.apply(.savePosition(position, itemID: materialID, progress: Double(read + 1) / Double(document.blocks.count)))
    }

    func spotSpan(of piece: Int) -> TextSpan? {
        guard let spot = state.spot, spot.piece == piece, spot.span.length > 0 else {
            return nil
        }
        return spot.span
    }

    private func startSpot() {
        guard let spot = state.spot else {
            return
        }
        scroll(spot.piece)
        guard let plan = spotPiece(spot.piece), let first = plan.words.first else {
            send(.spot(false))
            return
        }
        send(.spotMove(SpotState(piece: spot.piece, word: 0, span: first.span, running: true)))
    }

    private func stopSpot() {
        spotClock?.cancel()
        spotClock = nil
    }

    private func advanceSpot() {
        guard let spot = state.spot, let plan = spotPiece(spot.piece) else {
            send(.spot(false))
            return
        }
        if spot.word + 1 < plan.words.count {
            let next = plan.words[spot.word + 1]
            send(.spotMove(SpotState(piece: spot.piece, word: spot.word + 1, span: next.span, running: true)))
            return
        }
        guard let following = document.plate(after: spot.piece), let next = spotPiece(following)?.words.first else {
            send(.spot(false))
            return
        }
        send(.spotMove(SpotState(piece: following, word: 0, span: next.span, running: true)))
    }

    private func scheduleSpot() {
        spotClock?.cancel()
        guard let spot = state.spot, spot.running, let plan = spotPiece(spot.piece),
              plan.words.indices.contains(spot.word) else {
            return
        }
        let defaults = UserDefaults.standard
        let profile = SpeedPauseProfile(json: defaults.string(forKey: ReaderAppearance.SpeedSetting.pauses.key(kind)))
        let wordsPerMinute = max(defaults.integer(forKey: ReaderAppearance.SpeedSetting.wordsPerMinute.key(kind)), 60)
        let beats = 1 + plan.words[spot.word].token.extraBeats(profile)
        let seconds = beats * 60 / Double(wordsPerMinute)
        spotClock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, self?.state.spot?.running == true else {
                return
            }
            self?.advanceSpot()
        }
    }

    private func spotPiece(_ piece: Int) -> SpotPiece? {
        if let cached = spotPieces[piece] {
            return cached
        }
        guard document.plates.contains(piece), case let .text(markdown) = document.blocks[piece] else {
            return nil
        }
        let plain = plainText(markdown)
        let spans = WordSpans.spans(in: plain)
        let tokens = SpeedText.tokens(in: .text(plain), at: piece).filter { !$0.isStop }
        let words = zip(spans, tokens).map { SpotWord(span: $0, token: $1) }
        let plan = SpotPiece(piece: piece, words: words)
        spotPieces[piece] = plan
        return plan
    }

    private func search(_ query: String) {
        guard let texts else {
            let document = document, plainText = plainText
            Task {
                let texts = await Task.detached(priority: .userInitiated) {
                    var texts: [Int: String] = [:]
                    for (index, block) in document.blocks.enumerated() {
                        if case let .text(markdown) = block {
                            texts[index] = plainText(markdown)
                        }
                    }
                    return texts
                }.value
                self.texts = texts
                send(.found(ReadingSearch.matches(of: query, in: texts), query: query))
            }
            return
        }
        send(.found(ReadingSearch.matches(of: query, in: texts), query: query))
    }
}
