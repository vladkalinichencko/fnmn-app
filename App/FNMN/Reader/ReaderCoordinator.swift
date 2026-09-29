import FNMNCore
import SwiftUI

/// The one owner of an open document's interaction: the plate mode, the fold, the place reading stopped at
/// and where the column is scrolled. Blocks reach it through the environment and send it actions, so no
/// block carries a closure and SwiftUI can compare blocks by value and skip the ones that did not change.
@MainActor @Observable
final class ReaderCoordinator {
    let document: ReaderDocument
    let materialID: String
    let title: String
    let source: SourceRef?
    let baseURL: URL
    private let library: LibraryModel

    private(set) var mode = PlateMode.reading
    private(set) var fold = ReadingFold.open
    /// The paragraph at the top of the open text when reading stopped.
    private(set) var place: Int?
    /// The block the column is scrolled to; the scroll view writes it while the reader scrolls.
    var scrollID: Int?
    /// A scroll the reader asked for, not one the person made: it moves the column without moving the place.
    @ObservationIgnored private var holdingPlace = false
    @ObservationIgnored private var start: Int?

    init(document: ReaderDocument, materialID: String, title: String, source: SourceRef?, baseURL: URL, start: Int?, library: LibraryModel) {
        self.document = document
        self.materialID = materialID
        self.title = title
        self.source = source
        self.baseURL = baseURL
        self.start = start
        self.library = library
    }

    /// The blocks the fold leaves on the page, without the title the header already shows and the cover above it.
    var visible: [Int] {
        visiblePieceIndexes(in: document.blocks, fold: fold).filter { $0 != document.repeatedTitle && $0 != document.lead }
    }

    func current(in visible: [Int]) -> Int? {
        readingPlaceTarget(place: place, visible: visible)
    }

    /// Scrolls to the saved place once, after the column is on screen.
    func restore() {
        guard let start else { return }
        self.start = nil
        place = start
        scroll(to: start)
    }

    /// The scroll view moved the column. Scrolling the outline moves between headings, not through the text,
    /// so the place stays where reading stopped.
    func scrolled(to index: Int?) {
        guard let index, document.blocks.indices.contains(index) else { return }
        if holdingPlace || fold != .open {
            holdingPlace = false
            return
        }
        guard index != place else { return }
        place = index
        let total = document.blocks.count
        library.apply(.savePosition(.piece(index), itemID: materialID, progress: Double(index + 1) / Double(total)))
    }

    func send(_ action: PlateAction) {
        withAnimation(.snappy) { mode = plateReduce(mode, action) }
    }

    /// Pinching in folds the document one heading level at a time; spreading unfolds it.
    func pinched(_ scale: CGFloat) {
        let next: ReadingFold
        if scale < 0.9 {
            next = readingFoldPinchIn(fold, blocks: document.blocks)
        } else if scale > 1.1 {
            next = readingFoldPinchOut(fold, blocks: document.blocks)
        } else {
            return
        }
        guard next != fold else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { fold = next }
        if let target = readingPlaceTarget(place: place, visible: visiblePieceIndexes(in: document.blocks, fold: next)) {
            scroll(to: target)
        }
    }

    /// Tapping a heading in the folded document opens the whole text at that section.
    func openSection(_ index: Int) {
        guard fold != .open else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { fold = .open }
        holdingPlace = true
        scrollID = index
    }

    func target(_ piece: Int, text: String, quote: String? = nil) -> AnnotationTarget {
        let span = quote.flatMap { quote -> TextSpan? in
            let found = (text as NSString).range(of: quote)
            return found.location == NSNotFound ? nil : TextSpan(start: found.location, length: found.length)
        }
        return AnnotationTarget(materialID: materialID, piece: piece, text: text, span: span)
    }

    func perform(_ command: AnnotationCommand, _ target: AnnotationTarget) {
        let change: LibraryChange = switch command {
        case let .mark(mark): .mark(mark, target)
        case let .unmark(mark): .unmark(mark, target)
        }
        Task { await library.apply(change) }
    }

    func note(_ text: String, _ target: AnnotationTarget) {
        Task { await library.apply(.note(text, target)) }
    }

    func readThrough(_ piece: Int?) {
        library.apply(.readThrough(piece: piece, itemID: materialID))
    }

    func ask(_ passage: String) {
        ChatGPTHandoff.copyAndOpen(title: title, passage: passage)
    }

    func copyPrompt(_ passage: String) {
        _ = ChatGPTHandoff.remember(title: title, passage: passage)
    }

    private func scroll(to target: Int) {
        guard scrollID != target else { return }
        holdingPlace = true
        scrollID = target
    }
}
