import FNMNCore
import SwiftUI

/// Everything an open document's screen does with it: the plate mode, the fold, the paragraph reading
/// stopped at and the block the column is scrolled to.
struct ReaderState: Equatable {
    var mode = PlateMode.reading
    var fold = ReadingFold.open
    /// The paragraph at the top of the open text when reading stopped.
    var place: Int?
    /// The block at the top of the column: the one the person scrolled to, or the one an action moves the column to.
    var scrollID: Int?
    /// Opened at a note rather than to read on: scrolling looks around and leaves the place where reading stopped.
    var keepsPlace = false
    /// The block the column goes to once it is laid out. A lazy column drops a position given before its rows
    /// exist and opens at the top, so the jump waits for `.opened`, and until then the top is not taken as the place.
    var opening: Int?
}

enum ReaderAction {
    /// The column is laid out and can go to where it opens.
    case opened
    /// The person scrolled this block to the top of the column.
    case scrolled(Int)
    case plate(PlateAction)
    /// Two fingers let go at this scale.
    case pinched(CGFloat)
    /// A heading of the folded document was tapped.
    case openSection(Int)
    case mark(AnnotationCommand, AnnotationTarget)
    case note(String, AnnotationTarget)
    case readThrough(Int?)
    case ask(String)
    case copyPrompt(String)
}

/// Pure: the next screen state for an action. Scrolling the outline moves between headings, not through the
/// text, so the place stays where reading stopped; pinching and opening a section keep the column on the place.
func readerReduce(_ state: ReaderState, _ action: ReaderAction, document: ReaderDocument) -> ReaderState {
    var state = state
    switch action {
    case .opened:
        guard let opening = state.opening else { return state }
        state.opening = nil
        state.scrollID = opening
    case let .scrolled(index):
        guard state.opening == nil else { return state }
        state.scrollID = index
        if document.blocks.indices.contains(index), state.fold == .open, !state.keepsPlace {
            state.place = index
        }
    case let .plate(action):
        state.mode = plateReduce(state.mode, action)
    case let .pinched(scale):
        let next = scale < 0.9 ? readingFoldPinchIn(state.fold, blocks: document.blocks)
            : scale > 1.1 ? readingFoldPinchOut(state.fold, blocks: document.blocks)
            : state.fold
        guard next != state.fold else { return state }
        state.fold = next
        state.scrollID = readingPlaceTarget(place: state.place, visible: visiblePieceIndexes(in: document.blocks, fold: next)) ?? state.scrollID
    case let .openSection(index):
        guard state.fold != .open else { return state }
        state.fold = .open
        state.scrollID = index
    case .mark, .note, .readThrough, .ask, .copyPrompt:
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
    @ObservationIgnored private let library: LibraryModel

    /// The column opens at the note it was opened at, or else at the place reading stopped.
    init(document: ReaderDocument, materialID: String, title: String, source: SourceRef?, baseURL: URL, place: Int?, note: Int?, library: LibraryModel) {
        self.document = document
        self.materialID = materialID
        self.title = title
        self.source = source
        self.baseURL = baseURL
        state = ReaderState(place: place, keepsPlace: note != nil)
        self.library = library
        state.opening = (note ?? place).flatMap { readingPlaceTarget(place: $0, visible: visible) }
    }

    func send(_ action: ReaderAction) {
        let before = state
        let next = readerReduce(state, action, document: document)
        // A row entering at the bottom changes nothing here; writing the same state would still redraw the reader.
        if next != before { withAnimation(animation(for: action)) { state = next } }
        perform(action, from: before, to: next)
    }

    /// The blocks the fold leaves on the page, without the title the header already shows and the cover above it.
    var visible: [Int] {
        visiblePieceIndexes(in: document.blocks, fold: state.fold).filter { $0 != document.repeatedTitle && $0 != document.lead }
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

    private func animation(for action: ReaderAction) -> Animation? {
        switch action {
        case .plate: .snappy
        case .pinched, .openSection: .spring(duration: 0.45, bounce: 0.15)
        case .opened, .scrolled, .mark, .note, .readThrough, .ask, .copyPrompt: nil
        }
    }

    private func perform(_ action: ReaderAction, from before: ReaderState, to next: ReaderState) {
        switch action {
        case .scrolled:
            guard let place = next.place, place != before.place else { return }
            let total = document.blocks.count
            library.apply(.savePosition(.piece(place), itemID: materialID, progress: Double(place + 1) / Double(total)))
        case let .mark(command, target):
            let change: LibraryChange = switch command {
            case let .mark(mark): .mark(mark, target)
            case let .unmark(mark): .unmark(mark, target)
            }
            Task { await library.apply(change) }
        case let .note(text, target):
            Task { await library.apply(.note(text, target)) }
        case let .readThrough(piece):
            library.apply(.readThrough(piece: piece, itemID: materialID))
        case let .ask(passage):
            ChatGPTHandoff.copyAndOpen(title: title, passage: passage)
        case let .copyPrompt(passage):
            _ = ChatGPTHandoff.remember(title: title, passage: passage)
        case .opened, .pinched, .openSection:
            guard next != before, let target = next.scrollID else { return }
            withAnimation(animation(for: action)) { position.scrollTo(id: target, anchor: .top) }
        case .plate:
            break
        }
    }
}
