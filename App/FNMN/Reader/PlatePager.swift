import FNMNCore
import SwiftUI

struct PlatePager: View {
    @Environment(LibraryModel.self) private var library
    let reader: ReaderCoordinator
    let plate: Int
    let width: CGFloat?
    @State private var forward = true
    @State private var viewport: CGFloat = 0
    private static let turn: CGFloat = 36
    private static let slide = Animation.spring(duration: 0.3, bounce: 0.08)

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

    private var page: some View {
        ScrollView {
            block
                .equatable()
                .padding(.horizontal, Tokens.gutter)
                .padding(.vertical, Tokens.gap)
                .frame(maxWidth: width ?? .infinity)
                .frame(maxWidth: .infinity, minHeight: viewport)
        }
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
        .onScrollPhaseChange { (old: ScrollPhase, new: ScrollPhase, context: ScrollPhaseChangeContext) in
            guard old == .interacting, new != .interacting else { return }
            let pull = Self.pull(context.geometry)
            let fling = abs(context.velocity?.dy ?? 0)
            let needed = max(Self.turn - fling / 10, Self.turn * 0.4)
            guard abs(pull) >= needed else {
                return
            }
            reader.send(.turnPlate(forward: pull > 0))
        }
    }

    private var block: BlockView {
        let document = reader.document
        let progress = library.progress
        let line = reader.state.showsLine ? reader.state.line : nil
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

    nonisolated private static func pull(_ geometry: ScrollGeometry) -> CGFloat {
        let top = -geometry.contentInsets.top
        let bottom = max(geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height, top)
        let y = geometry.contentOffset.y
        return y > bottom ? y - bottom : y < top ? y - top : 0
    }
}

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
