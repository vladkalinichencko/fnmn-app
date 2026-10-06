import FNMNCore
import SwiftUI

/// The edge of the screen the reading line's pin stands at, so the thumb that drags it can be either.
enum ReadingLineSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }

    var name: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }

    var alignment: Alignment {
        switch self {
        case .left: .leading
        case .right: .trailing
        }
    }

    /// The edge the pin keeps clear of; the line runs out through the other one.
    var edge: Edge.Set {
        switch self {
        case .left: .leading
        case .right: .trailing
        }
    }

    var opposite: Edge.Set {
        switch self {
        case .left: .trailing
        case .right: .leading
        }
    }
}

/// The red line across the screen that the reader drags down the text by the pin at one end, the left or the right
/// as chosen in Settings. Between lines of text it stops halfway, with a light tick at each stop; across a picture, a
/// video or a wide formula it stands wherever the finger leaves it. It scrolls with the text it stands in.
struct ReadingLineView: View {
    let reader: ReaderCoordinator
    /// Where the line stood when the finger took the pin; nil while no finger is on it.
    @State private var start: CGFloat?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ReaderAppearance.lineSideKey) private var side = ReadingLineSide.left

    /// The pin is a short capsule lying along the line.
    private static let pin = CGSize(width: 22, height: 9)
    private static let grip: CGFloat = 44
    /// The pin keeps clear of its edge; the line runs out through the other one.
    private static let inset: CGFloat = 4

    /// A deep red glows on a dark page; on a light page it reads as dark, so there the line is a bright red with a
    /// wider, stronger glow.
    private var red: Color {
        colorScheme == .dark ? Color(red: 0.78, green: 0.02, blue: 0.06) : Color(red: 1, green: 0.13, blue: 0.18)
    }
    private var glow: Color { red.opacity(colorScheme == .dark ? 0.6 : 0.9) }
    private var glowRadius: CGFloat { colorScheme == .dark ? 3 : 5 }

    var body: some View {
        if let line = reader.state.line, let y = reader.y(of: line) {
            ZStack(alignment: side.alignment) {
                Rectangle()
                    .fill(red)
                    .frame(height: 1.5)
                    .shadow(color: glow, radius: glowRadius)
                    .allowsHitTesting(false)
                Capsule()
                    .fill(red)
                    .frame(width: Self.pin.width, height: Self.pin.height)
                    .shadow(color: glow, radius: glowRadius + 1)
                    .frame(width: Self.grip, height: Self.grip, alignment: side.alignment)
                    .contentShape(.rect)
                    .gesture(drag(from: y))
            }
            .frame(height: Self.grip)
            .padding(side.edge, Self.inset)
            .offset(y: y - Self.grip / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // In landscape the column stops at the safe area; the line goes on to the screen's edge.
            .ignoresSafeArea(.container, edges: side.opposite)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: reader.stop(of: line)) { _, _ in start != nil }
        }
    }

    /// The line follows the finger from where it stood, and is saved where the finger lets go.
    private func drag(from y: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(ReadingSession.column))
            .onChanged { value in
                let origin = start ?? y
                start = origin
                guard let moved = reader.line(near: origin + value.translation.height), moved != reader.state.line else { return }
                reader.send(.moveLine(moved))
            }
            .onEnded { _ in
                start = nil
                reader.send(.settleLine)
            }
    }
}
