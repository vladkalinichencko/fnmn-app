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
        state.folded = closed ? document.foldableHeadings : []
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
        // A material nobody has folded by hand opens closed up. The block the reader opens at stays on the page.
        let saved = library.progress.folded[materialID].map(Set.init) ?? document.foldableHeadings
        state.folded = (note ?? place).map { saved.subtracting(document.headings(holding: $0)) } ?? saved
        state.opening = (note ?? place).flatMap { readingPlaceTarget(place: $0, visible: visible) }
        state.hidesColumn = state.opening != nil
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
        case .plate, .toggleSection, .foldAll: .snappy
        case .opened, .scrolled, .mark, .note, .readThrough, .ask, .copyPrompt: nil
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
            library.apply(.readThrough(piece: piece, itemID: materialID))
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

    /// The share read follows the plates shown as read: those above the place and those up to the
    /// "read through here" mark, whichever reaches further.
    private func savePlace(_ place: Int?) {
        let read = [place, library.progress.readThrough[materialID]].compactMap { $0 }.max() ?? -1
        let position = place.map(ReadingPosition.piece) ?? library.position(of: materialID) ?? .piece(0)
        library.apply(.savePosition(position, itemID: materialID, progress: Double(read + 1) / Double(document.blocks.count)))
    }
}
