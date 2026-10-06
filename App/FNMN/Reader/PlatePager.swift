import FNMNCore
import SwiftUI

/// One plate at a time over the blurred column, drawn as it stands in the column, under its place in the contents.
/// The plate lies in its own scroll view, so one taller than the screen scrolls as it does in the column; a finger
/// that has reached its end and pulls on past it turns to the next plate, and one that pulls on past its start turns
/// back, the way a pull past the top of a list refreshes it. A scroll view that snaps a page at a time would have no
/// room for a page taller than itself, and scroll views of the same direction one inside another do not hand the
/// finger over at the end.
struct PlatePager: View {
    @Environment(LibraryModel.self) private var library
    let reader: ReaderCoordinator
    let plate: Int
    /// The width of the column with its gutters, so the plate is as wide as in the column.
    let width: CGFloat?
    /// Which way the finger last pulled. It is set while the finger pulls, before the plate turns, so the plate going
    /// away slides the right way: a view leaves with the transition it was last drawn with.
    @State private var forward = true
    /// The height the scroll view shows inside its insets, which a short plate fills, standing in its middle.
    @State private var viewport: CGFloat = 0
    /// How far past the end or the start a pull has to go for letting go to turn the plate.
    private static let turn: CGFloat = 56
    private static let slide = Animation.spring(duration: 0.42, bounce: 0.12)

    var body: some View {
        VStack(spacing: 0) {
            PlateContents(document: reader.document, plate: plate)
                .padding(.horizontal, Tokens.gutter)
                .frame(maxWidth: width ?? .infinity)
            ZStack {
                page
                    .id(plate)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .bottom : .top).combined(with: .opacity),
                        removal: .move(edge: forward ? .top : .bottom).combined(with: .opacity)
                    ))
            }
            .animation(Self.slide, value: plate)
            .clipped()
        }
    }

    /// The plate in its scroll view. Turned back to, a tall plate opens at its end, where reading left it.
    private var page: some View {
        ScrollView {
            block
                .equatable()
                .padding(.horizontal, Tokens.gutter)
                .padding(.vertical, Tokens.gap)
                .frame(maxWidth: width ?? .infinity)
                .frame(maxWidth: .infinity, minHeight: viewport)
        }
        // A plate shorter than the screen gives the pull nothing to scroll; it still has to stretch.
        .scrollBounceBehavior(.always, axes: .vertical)
        .defaultScrollAnchor(forward ? .top : .bottom, for: .initialOffset)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
        } action: { _, height in
            viewport = max(height, 0)
        }
        .onScrollGeometryChange(for: CGFloat.self, of: Self.pull) { _, pull in
            if pull > 4 { forward = true } else if pull < -4 { forward = false }
        }
        // The plate turns when the finger lets go of a pull far enough, never while a flick runs into the end.
        .onScrollPhaseChange { old, new, context in
            guard old == .interacting, new != .interacting else { return }
            let pull = Self.pull(context.geometry)
            guard abs(pull) >= Self.turn else { return }
            reader.send(.turnPlate(forward: pull > 0))
        }
    }

    /// The plate as the column draws it, read as far as the column would show it read.
    private var block: BlockView {
        let document = reader.document
        let progress = library.progress
        let line = reader.state.showsLine ? reader.state.line : nil
        // As in the column: with the line, the plate right above it holds "read to here" when it stands between plates.
        let marked: Int? = if let line {
            line.fraction == 0 ? document.plate(before: line.piece) : line.fraction >= 1 ? line.piece : nil
        } else {
            progress.readThrough[reader.materialID]
        }
        return BlockView(
            block: document.blocks[plate],
            index: plate,
            baseURL: reader.baseURL,
            mode: reader.state.mode,
            readShare: line.map { progress.readShare(of: plate, in: reader.materialID, line: $0) }
                ?? (progress.isPieceRead(plate, of: reader.materialID, current: reader.state.place) ? 1 : 0),
            markedReadThrough: marked == plate,
            annotations: library.snapshot.annotations.filter { $0.materialID == reader.materialID && $0.piece == plate },
            fold: .none
        )
    }

    /// How far the content is pulled past its end, or, below zero, past its start.
    nonisolated private static func pull(_ geometry: ScrollGeometry) -> CGFloat {
        let top = -geometry.contentInsets.top
        let bottom = max(geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height, top)
        let y = geometry.contentOffset.y
        return y > bottom ? y - bottom : y < top ? y - top : 0
    }
}

/// Where the plate shown stands: the sections over it, outermost first, and its number among all the plates. The
/// innermost section's heading is the title in the bar above.
private struct PlateContents: View {
    let document: ReaderDocument
    let plate: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(document.headingPath(of: plate).dropLast().map(title).joined(separator: " › "))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let number = document.plateNumber(of: plate) {
                Text("\(number) / \(document.plates.count)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }

    private func title(_ heading: Int) -> String {
        guard case let .heading(_, title) = document.blocks[heading] else { return "" }
        return MarkedMarkdown.plainText(title, baseURL: nil)
    }
}
