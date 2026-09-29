import FNMNCore
import SwiftUI

/// Everything an open document's screen does with it: the plate mode, the fold, the paragraph reading
/// stopped at and the block the column is scrolled to.
struct ReaderState: Equatable {
    var mode = PlateMode.reading
    var fold = ReadingFold.open
    /// The paragraph at the top of the open text when reading stopped.
    var place: Int?
    /// The block the column shows at the top.
    var scrollID: Int?
    /// The saved place, until the column first appears and goes there.
    var start: Int?
}

enum ReaderAction {
    /// The column is on screen: go to the saved place, once.
    case restore
    /// The person scrolled the column to this block.
    case scrolled(Int?)
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
    case .restore:
        guard let start = state.start else { return state }
        state.start = nil
        state.place = start
        state.scrollID = start
    case let .scrolled(index):
        state.scrollID = index
        if let index, document.blocks.indices.contains(index), state.fold == .open {
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
    @ObservationIgnored private let library: LibraryModel

    init(document: ReaderDocument, materialID: String, title: String, source: SourceRef?, baseURL: URL, start: Int?, library: LibraryModel) {
        self.document = document
        self.materialID = materialID
        self.title = title
        self.source = source
        self.baseURL = baseURL
        state = ReaderState(start: start)
        self.library = library
    }

    func send(_ action: ReaderAction) {
        let before = state
        let next = readerReduce(state, action, document: document)
        withAnimation(animation(for: action)) { state = next }
        perform(action, from: before, to: next)
    }

    /// The column scrolls through this binding: what the scroll view writes comes back as an action.
    var scrollPosition: Binding<Int?> {
        Binding(get: { self.state.scrollID }, set: { self.send(.scrolled($0)) })
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
        case .restore, .scrolled, .mark, .note, .readThrough, .ask, .copyPrompt: nil
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
        case .restore, .plate, .pinched, .openSection:
            break
        }
    }
}
