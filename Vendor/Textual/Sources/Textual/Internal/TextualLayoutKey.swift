import SwiftUI

/// The layouts of the text that `InlineText` and `StructuredText` draw, apart from every other `Text` around them.
/// What works over a whole column of them reads this key instead of `Text.LayoutKey`, so a label or a hidden
/// placeholder next to the text never counts as a line.
struct TextualLayoutKey: PreferenceKey {
  static var defaultValue: Text.LayoutKey.Value { [] }

  static func reduce(value: inout Text.LayoutKey.Value, nextValue: () -> Text.LayoutKey.Value) {
    value.append(contentsOf: nextValue())
  }
}

extension View {
  /// Publishes the layouts of the text inside under `TextualLayoutKey` as well.
  func publishingTextualLayout() -> some View {
    backgroundPreferenceValue(Text.LayoutKey.self) { value in
      Color.clear.preference(key: TextualLayoutKey.self, value: value)
    }
  }
}
