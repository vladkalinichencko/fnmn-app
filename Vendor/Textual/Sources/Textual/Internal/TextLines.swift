import SwiftUI

// MARK: - Overview
//
// `TextLines` reads the `Text.Layout` of every `InlineText` and `StructuredText` inside a view and reports where
// each line of text lies vertically, in that view's own coordinates. A region that scrolls sideways reports no
// layout, so it gives its frame through `SidewaysTextKey` instead and counts as one tall line.

struct TextLines: ViewModifier {
  let action: ([ClosedRange<CGFloat>]) -> Void
  @State private var text: [ClosedRange<CGFloat>] = []
  @State private var sideways: [ClosedRange<CGFloat>] = []

  func body(content: Content) -> some View {
    content
      .overlayPreferenceValue(TextualLayoutKey.self) { value in
        GeometryReader { geometry in
          Color.clear
            .onChange(of: Self.lines(value, geometry: geometry), initial: true) { _, lines in
              text = lines
              action(text + sideways)
            }
        }
        .allowsHitTesting(false)
      }
      .overlayPreferenceValue(SidewaysTextKey.self) { anchors in
        GeometryReader { geometry in
          Color.clear
            .onChange(of: anchors.map { geometry[$0] }.map { $0.minY...$0.maxY }, initial: true) { _, frames in
              sideways = frames
              action(text + sideways)
            }
        }
        .allowsHitTesting(false)
      }
  }

  private static func lines(
    _ value: Text.LayoutKey.Value,
    geometry: GeometryProxy
  ) -> [ClosedRange<CGFloat>] {
    value.filter(\.layout.isTextFragment).flatMap { anchored in
      let origin = geometry[anchored.origin]
      return anchored.layout.map { line in
        let bounds = line.typographicBounds.rect
        return (origin.y + bounds.minY)...(origin.y + bounds.maxY)
      }
    }
  }
}

/// The frames of text that scrolls sideways, whose lines `Text.LayoutKey` no longer carries.
struct SidewaysTextKey: PreferenceKey {
  static let defaultValue: [Anchor<CGRect>] = []

  static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
    value.append(contentsOf: nextValue())
  }
}
