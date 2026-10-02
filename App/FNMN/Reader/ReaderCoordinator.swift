import FNMNCore
import SwiftUI

/// Everything an open document's screen does with it: the plate mode, the headings folded, the paragraph reading
/// stopped at and the block the column is scrolled to.
struct ReaderState: Equatable {
    var mode = PlateMode.reading
    /// The headings whose sections are closed up under them.
    var folded: Set<Int> = []
    /// The paragraph at the top of the open text when reading stopped.
    var place: Int?
    /// The block at the top of the column: the one the person scrolled to, or the one an action moves the column to.
    var scrollID: Int?
    /// Opened at a note rather than to read on: scrolling looks around and leaves the place where reading stopped.
    var keepsPlace = false
    /// The block the column goes to once it is laid out. A lazy column drops a position given before its rows
    /// exist and opens at the top, so the jump waits for `.opened`, and until then the top is not taken as the place.
    var opening: Int?
    /// The column stays unseen until it has gone to `opening`, where the jump would show.
    var hidesColumn = false
    /// The reader moves a line down the text instead of each block graying once it scrolls past the top.
    var showsLine = false
    var line: ReadingLine?
}

enum ReaderAction {
    /// The column is laid out and can go to where it opens.
    case opened
    /// The person scrolled this block to the top of the column.
    case scrolled(Int)
    case plate(PlateAction)
    /// A heading was tapped: its section closes up under it, or opens again.
    case toggleSection(Int)
    /// Every section closes up under its heading, or every one opens.
    case foldAll(Bool)
    case mark(AnnotationCommand, AnnotationTarget)
    case note(String, AnnotationTarget)
    case readThrough(Int?)
    case showLine(Bool)
    /// The line moved, under the finger or onto the nearest place between lines of text.
    case moveLine(ReadingLine)
    /// The line came to rest, and is saved where it stands.
    case settleLine
    case ask(String)
    case copyPrompt(String)
}

/// Pure: the next screen state for an action. A heading folds or opens below itself, so the column stays where it is.
func readerReduce(_ state: ReaderState, _ action: ReaderAction, document: ReaderDocument) -> ReaderState {
    var state = state
    switch action {
    case .opened:
        guard let opening = state.opening else { return state }
        state.opening = nil
        state.hidesColumn = false
        state.scrollID = opening
    case let .scrolled(index):
        guard state.opening == nil else { return state }
        state.scrollID = index
        if document.blocks.indices.contains(index), !state.keepsPlace {
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
        // With the line, "read to here" takes it to the top of the next block, and taking the mark away takes it back
        // to the top of the block above it.
        guard state.showsLine, let line = state.line else { return state }
        let visible = document.visibleBlocks(folded: state.folded)
        let block = if let piece { visible.first { $0 > piece } } else { visible.last { $0 < line.piece } }
        if let block { state.line = ReadingLine(piece: block, fraction: 0) }
    case let .showLine(shows):
        state.showsLine = shows
        // A line shown again stands where it was left, or at the top of the block reading stopped at when reading
        // without it went further, so showing it takes nothing read away either.
        if shows, let piece = state.place ?? document.visibleBlocks(folded: state.folded).first,
           state.line.map({ $0.piece < piece }) ?? true {
            state.line = ReadingLine(piece: piece, fraction: 0)
        }
    case let .moveLine(line):
        state.line = line
    case .mark, .note, .settleLine, .ask, .copyPrompt:
        break
    }
    return state
}

/// The one owner of an open document's screen. Views read `state` and `send` actions; the coordinator is the
/// only caller of `readerReduce` and starts effects (saving the place, marks, ChatGPT) only from what an action
/// and the state it produced ask for. Blocks reach it through the environment, so no block carries a closure
/// and SwiftUI compares blocks by value.
@MainActor @Observable
final class ReaderCoordinator {
    let document: ReaderDocument
    let materialID: String
    let title: String
    let source: SourceRef?
    let baseURL: URL
    private(set) var state: ReaderState
    /// Where the column is sent. Only actions move it; the person's own scrolling comes back as `.scrolled`
    /// and is never written here, so the column is not pulled to a block's top while the finger moves it.
    var position = ScrollPosition(idType: Int.self)
    /// Each block's row in the column's coordinate space, with the gap under it. A row the lazy column has let go
    /// keeps its last frame. Only the reading line watches them.
    private(set) var rows: [Int: CGRect] = [:]
    /// The lines of text laid out in the column, merged where they overlap, and the places between them the reading
    /// line stands at.
    @ObservationIgnored private var textLines: [ClosedRange<Double>] = []
    @ObservationIgnored private var stops: [ClosedRange<Double>] = []
    @ObservationIgnored private let library: LibraryModel

    /// The column opens at the note it was opened at, or else at the place reading stopped, which with the reading
    /// line is the line's block. A line saved in another block than the column opens at starts again at its top.
    init(document: ReaderDocument, materialID: String, title: String, source: SourceRef?, baseURL: URL, place: Int?, note: Int?, showsLine: Bool, library: LibraryModel) {
        self.document = document
        self.materialID = materialID
        self.title = title
        self.source = source
        self.baseURL = baseURL
        state = ReaderState(place: place, keepsPlace: note != nil)
        self.library = library
        // A material nobody has folded by hand opens with its lowest sections closed up, the contents showing. The block the reader opens at stays on the page.
        let saved = library.progress.folded[materialID].map(Set.init) ?? document.lowestHeadings
        state.folded = (note ?? place).map { saved.subtracting(document.headings(holding: $0)) } ?? saved
        state.opening = (note ?? place).flatMap { readingPlaceTarget(place: $0, visible: visible) }
        state.hidesColumn = state.opening != nil
        state.line = library.progress.lines[materialID]
        if note == nil, place != nil, state.line?.piece != place { state.line = nil }
        state = readerReduce(state, .showLine(showsLine), document: document)
    }

    func send(_ action: ReaderAction) {
        let before = state
        let next = readerReduce(state, action, document: document)
        // A row entering at the bottom changes nothing here; writing the same state would still redraw the reader.
        if next != before { withAnimation(animation(for: action)) { state = next } }
        perform(action, from: before, to: next)
    }

    /// The blocks the folded headings leave on the page, without the title the header already shows and the cover above it.
    var visible: [Int] { document.visibleBlocks(folded: state.folded) }

    /// The heading of the section at the top of the screen, once that heading has scrolled above it. The title the
    /// header already shows is not one.
    var passedHeading: (index: Int, title: String)? {
        state.scrollID.flatMap { document.heading(before: $0) }.flatMap { $0.index == document.repeatedTitle ? nil : $0 }
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

    /// The height of the column the line stands at, or nil while its block is not laid out. At a block's top it
    /// stands at the stop between the block and the text above it.
    func y(of line: ReadingLine) -> CGFloat? {
        guard let row = rows[line.piece] else { return nil }
        guard line.fraction > 0 else { return top(of: line.piece) }
        return row.minY + line.fraction * (row.height - Tokens.gap)
    }

    /// The line at the place nearest to a height of the column. It belongs to the first block whose text reaches
    /// below it; the stop between two blocks is the top of the lower one, wherever the middle of the gap falls.
    func line(near y: CGFloat) -> ReadingLine? {
        guard let place = ReadingLine.nearest(to: y, in: stops).map({ CGFloat($0) }),
              let piece = visible.first(where: { rows[$0].map { place < $0.maxY - Tokens.gap } ?? false }),
              let row = rows[piece]
        else { return nil }
        if let next = visible.first(where: { $0 > piece }), let top = top(of: next), place >= top - 0.5 {
            return ReadingLine(piece: next, fraction: 0)
        }
        if let top = top(of: piece), place <= top + 0.5 {
            return ReadingLine(piece: piece, fraction: 0)
        }
        return ReadingLine(piece: piece, fraction: (place - row.minY) / max(row.height - Tokens.gap, 1))
    }

    private func top(of piece: Int) -> CGFloat? {
        rows[piece].map { CGFloat(ReadingLine.stop(atTopOf: Double($0.minY), lines: textLines, stops: stops)) }
    }

    /// The stop the line stands at, so the finger feels a tick at each new one and none while it crosses a picture.
    func stop(of line: ReadingLine) -> Int? {
        guard let y = y(of: line).map(Double.init) else { return nil }
        return stops.firstIndex { $0.lowerBound - 1 <= y && y <= $0.upperBound + 1 }
    }

    /// A block was laid out, or laid out again with a new font or width.
    func rowChanged(_ index: Int, _ row: CGRect) {
        rows[index] = row
        keepLineBetweenLines()
    }

    /// New lines of text came into the column, or the old ones moved with a new font or width.
    func textLinesChanged(_ lines: [ClosedRange<CGFloat>]) {
        textLines = ReadingLine.merged(lines.map { Double($0.lowerBound)...Double($0.upperBound) })
        stops = ReadingLine.stops(between: textLines)
        keepLineBetweenLines()
    }

    /// The line keeps its share of its block when the text is laid out again, which can put it off the places
    /// between lines; it then goes to the nearest one. It is saved only where the reader leaves it, so a font size
    /// being dragged through does not record a line at every step.
    private func keepLineBetweenLines() {
        guard state.showsLine, state.opening == nil, let line = state.line, let y = y(of: line),
              let moved = self.line(near: y), moved != line, let movedY = self.y(of: moved), abs(movedY - y) > 0.5
        else { return }
        send(.moveLine(moved))
    }

    private func animation(for action: ReaderAction) -> Animation? {
        switch action {
        case .plate, .toggleSection, .foldAll: .snappy
        case .opened, .scrolled, .mark, .note, .readThrough, .showLine, .moveLine, .settleLine, .ask, .copyPrompt: nil
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
            position.scrollTo(id: target, anchor: .top)
        case .plate:
            break
        case .toggleSection, .foldAll:
            guard next.folded != before.folded else { return }
            library.apply(.fold(next.folded.sorted(), itemID: materialID))
            // The top block may have gone under a closed heading; the column goes to the one that stands for it.
            if let place = next.place, !visible.contains(place), let target = current(in: visible) {
                position.scrollTo(id: target, anchor: .top)
            }
        }
    }

    /// The share read follows the plates shown as read: those above the reading line's block while it shows, or else
    /// those above the place, up to the "read through here" mark and above where the line was left, whichever reaches
    /// further.
    private func savePlace(_ place: Int?) {
        let read = if state.showsLine, let line = state.line {
            line.piece - 1
        } else {
            [place, library.progress.readThrough[materialID], state.line.map { $0.piece - 1 }].compactMap { $0 }.max() ?? -1
        }
        let position = place.map(ReadingPosition.piece) ?? library.position(of: materialID) ?? .piece(0)
        library.apply(.savePosition(position, itemID: materialID, progress: Double(read + 1) / Double(document.blocks.count)))
    }
}
