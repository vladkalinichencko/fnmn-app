#if canImport(UIKit)
  import SwiftUI
  import UIKit

  /// Items the app adds to the edit menu of selected text, given the selected text. Two menus are equal
  /// when their keys are, so SwiftUI can tell an unchanged menu from a new one; a bare closure cannot be
  /// compared and would wake every view that reads it on each update.
  public struct TextSelectionMenu: Equatable {
    public let key: AnyHashable
    public let items: @MainActor (String) -> [UIMenuElement]

    public init(key: some Hashable, items: @escaping @MainActor (String) -> [UIMenuElement]) {
      self.key = AnyHashable(key)
      self.items = items
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.key == rhs.key
    }
  }

  extension EnvironmentValues {
    @Entry public var textualSelectionMenu: TextSelectionMenu? = nil
  }
#endif
