import FNMNCore
import SwiftUI

private let platePagerSpace = "platePager"

struct PlatePager: View {
    @Environment(LibraryModel.self) private var library
    let reader: ReaderCoordinator
    let plate: Int
    let width: CGFloat?
    @State private var forward = true
    @State private var horizontal = false
    @State private var viewport: CGFloat = 0
    @State private var pageFrame: CGRect = .zero
    @State private var pagerWidth: CGFloat = 0
    private static let turn: CGFloat = 36
    private static let slide = Animation.spring(duration: 0.3)

    var body: some View {
        VStack(spacing: 0) {
            PlateContents(document: reader.document, plate: plate)
                .padding(.horizontal, Tokens.gutter)
                .frame(maxWidth: width ?? .infinity)
            ZStack {
                page
                    .id(plate)
                    .transition(.asymmetric(
                        insertion: .move(edge: insertionEdge).combined(with: .opacity),
                        removal: .move(edge: removalEdge).combined(with: .opacity)
                    ))
            }
            .animation(Self.slide, value: plate)
            .clipped()
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(platePagerSpace)) } action: { pageFrame = $0 }
            controls
        }
        .coordinateSpace(.named(platePagerSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pagerWidth = $0 }
        .gesture(turnPan)
    }

    private var insertionEdge: Edge {
        if horizontal { return forward ? .trailing : .leading }
        return forward ? .bottom : .top
    }

    private var removalEdge: Edge {
        if horizontal { return forward ? .leading : .trailing }
        return forward ? .top : .bottom
    }

    private var controls: some View {
        HStack {
            navButton("chevron.up", title: "Previous Plate", enabled: reader.document.plate(before: plate) != nil) {
                turn(false)
            }
            Spacer()
            navButton("chevron.down", title: "Next Plate", enabled: reader.document.plate(after: plate) != nil) {
                turn(true)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .padding(.horizontal, Tokens.gutter)
        .padding(.vertical, 8)
    }

    private func navButton(_ systemImage: String, title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .font(.title3)
            .frame(width: 56, height: 56)
            .glassEffect(.regular.interactive(), in: Circle())
            .disabled(!enabled)
    }

    private func turn(_ next: Bool) {
        forward = next
        horizontal = false
        reader.send(.turnPlate(forward: next))
    }

    private func inCard(_ point: CGPoint) -> Bool {
        guard pageFrame.contains(point) else { return false }
        let cardWidth = min(width ?? pagerWidth, pagerWidth)
        return abs(point.x - pagerWidth / 2) <= cardWidth / 2
    }

    private var turnPan: HorizontalPan {
        HorizontalPan(
            starts: { _ in true },
            allowed: { point in !inCard(point) },
            changed: { translation in
                if abs(translation) > 4 {
                    forward = translation < 0
                }
            },
            ended: { translation, velocity in
                let needed = max(72 - abs(velocity) / 8, 36)
                guard abs(translation) >= needed else { return }
                forward = translation < 0
                horizontal = true
                reader.send(.turnPlate(forward: forward))
            }
        )
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
            if abs(pull) > 4 {
                forward = pull > 0
                horizontal = false
            }
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
        HStack(spacing: 12) {
            Text(document.headingPath(of: plate).dropLast().map(title).joined(separator: " › "))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let number = document.plateNumber(of: plate) {
                ProgressView(value: Double(number), total: Double(max(document.plates.count, 1)))
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .frame(width: 72)
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
