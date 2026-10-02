import SwiftUI

extension StructuredText {
  struct MathBlock: View {
    @Environment(\.paragraphStyle) private var paragraphStyle
    @Environment(\.mathProperties) private var mathProperties

    private let content: AttributedSubstring

    init(_ content: AttributedSubstring) {
      self.content = content
    }

    var body: some View {
      let configuration = BlockStyleConfiguration(
        label: .init(label),
        indentationLevel: indentationLevel
      )
      let resolvedStyle = paragraphStyle.resolve(configuration: configuration)

      AnyView(resolvedStyle)
        .layoutValue(key: BlockAlignmentKey.self, value: mathProperties.textAlignment)
    }

    /// A formula wider than the page scrolls sideways instead of running past the edge. Its frame is reported like
    /// an `Overflow` region's: the text selection lies over the whole text and would take every touch that belongs
    /// to the scroll view, so it leaves this frame alone. `Overflow` itself is not used, since it scrolls only in
    /// the scroll overflow mode and the reader wraps.
    private var label: some View {
      ViewThatFits(in: .horizontal) {
        formula
        ScrollView(.horizontal) {
          formula
            .modifier(TextSelectionInteraction())
            .transformPreference(Text.LayoutKey.self) { value in
              value = []
            }
        }
        .scrollIndicators(.hidden)
        .anchorPreference(key: SidewaysTextKey.self, value: .bounds) { [$0] }
        .background(
          GeometryReader { geometry in
            Color.clear
              .preference(
                key: OverflowFrameKey.self,
                value: [geometry.frame(in: .textContainer)]
              )
          }
        )
      }
    }

    private var formula: some View {
      WithInlineStyle(AttributedString(content)) {
        TextFragment($0)
      }
      .fixedSize()
    }

    private var indentationLevel: Int {
      content.presentationIntent?.indentationLevel ?? 0
    }
  }
}
