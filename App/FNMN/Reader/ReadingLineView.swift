import FNMNCore
import SwiftUI

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

struct ReadingLineView: View {
    let reader: ReaderCoordinator
    @State private var start: CGFloat?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ReaderAppearance.lineSideKey) private var side = ReadingLineSide.left

    private static let pin = CGSize(width: 22, height: 9)
    private static let grip: CGFloat = 44
    private static let inset: CGFloat = 4

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
            .ignoresSafeArea(.container, edges: side.opposite)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: reader.stop(of: line)) { _, _ in start != nil }
        }
    }

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
