#if canImport(UIKit)
  import SwiftUI
  import UIKit

  extension EnvironmentValues {
    /// Items the app adds to the edit menu of selected text, given the selected text.
    @Entry public var textualSelectionMenu: (@MainActor (String) -> [UIMenuElement])? = nil
  }
#endif
