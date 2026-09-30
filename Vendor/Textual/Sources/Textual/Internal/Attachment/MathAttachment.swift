import SwiftUI
@_spi(Textual) private import SwiftUIMath

struct MathAttachment: Attachment {
  enum DisplayStyle: Sendable {
    case inline
    case block
  }

  var description: String {
    switch displayStyle {
    case .inline:
      return "$\(latex)$"
    case .block:
      return "$$\(latex)$$"
    }
  }

  var selectionStyle: AttachmentSelectionStyle {
    .text
  }

  let latex: String
  let displayStyle: DisplayStyle

  init(latex: String, style: DisplayStyle) {
    self.latex = latex
    self.displayStyle = style
  }

  var body: some View {
    MathView(latex: latex, style: displayStyle)
  }

  /// SwiftUI lowers an inline picture by its descent but still counts its whole height above the baseline, so
  /// the line grows by the descent on top. A block has a line to itself and stands on the baseline, since a
  /// formula centered on the math axis, such as a table of aligned rows, has half its height as descent.
  func baselineOffset(in environment: TextEnvironmentValues) -> CGFloat {
    switch displayStyle {
    case .inline:
      return -typographicBounds(in: environment).descent
    case .block:
      return 0
    }
  }

  /// A formula keeps one line at its own width, so its size never depends on the width the text is laid out at:
  /// a size that changed after the first layout changed the row's height once the row was on screen, and a lazy
  /// column scrolling up moved everything under it. A block scrolls sideways when it is wider than the page.
  func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
    typographicBounds(in: environment).size
  }

  private func typographicBounds(
    fitting proposal: ProposedViewSize = .unspecified,
    in environment: TextEnvironmentValues
  ) -> Math.TypographicBounds {
    Math.typographicBounds(
      for: latex,
      fitting: proposal,
      font: .init(
        name: .init(environment.mathProperties.fontName),
        size: FontScaled(environment.mathProperties.fontScale).resolve(in: environment)
      ),
      style: .init(displayStyle)
    )
  }
}

private struct MathView: View {
  @Environment(\.textEnvironment) private var environment

  let latex: String
  let style: MathAttachment.DisplayStyle

  var body: some View {
    Math(latex)
      .mathFont(
        .init(
          name: .init(environment.mathProperties.fontName),
          size: FontScaled(environment.mathProperties.fontScale).resolve(in: environment)
        )
      )
      .mathTypesettingStyle(.init(style))
      .mathRenderingMode(.monochrome)
  }
}

extension Math.Font.Name {
  fileprivate init(_ fontName: MathProperties.FontName) {
    self.init(rawValue: fontName.rawValue)
  }
}

extension Math.TypesettingStyle {
  fileprivate init(_ style: MathAttachment.DisplayStyle) {
    switch style {
    case .inline:
      self = .text
    case .block:
      self = .display
    }
  }
}
