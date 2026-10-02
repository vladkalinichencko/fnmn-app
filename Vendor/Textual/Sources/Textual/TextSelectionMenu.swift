#if canImport(UIKit)
  import SwiftUI
  import UIKit

  /// What a selection holds when its edit menu opens.
  public struct SelectedText {
    /// The selection as plain text.
    public let text: String
    /// The pictures inside the selection.
    public let images: [UIImage]

    var isEmpty: Bool {
      text.isEmpty && images.isEmpty
    }
  }

  extension NSAttributedString {
    /// The pictures attached to the text.
    var images: [UIImage] {
      var images: [UIImage] = []
      enumerateAttribute(.textual.attachment, in: NSRange(location: 0, length: length)) { value, _, _ in
        guard let attachment = value as? AnyAttachment, attachment.base is ImageAttachment,
          let data = attachment.pngData(), let image = UIImage(data: data)
        else { return }
        images.append(image)
      }
      return images
    }
  }

  /// Items the app adds to the edit menu of selected text. Two menus are equal when their keys are, so SwiftUI
  /// can tell an unchanged menu from a new one; a bare closure cannot be compared and would wake every view that
  /// reads it on each update.
  public struct TextSelectionMenu: Equatable {
    public let key: AnyHashable
    public let items: @MainActor (SelectedText) -> [UIMenuElement]

    public init(key: some Hashable, items: @escaping @MainActor (SelectedText) -> [UIMenuElement]) {
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
