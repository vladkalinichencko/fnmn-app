import SwiftUI

/// The one set of spacings and radii every screen uses.
enum Tokens {
    static let gutter: CGFloat = 16
    static let gap: CGFloat = 14
    static let sectionGap: CGFloat = 28
    static let tileRadius: CGFloat = 38
    static let tilePadding: CGFloat = 16
    static let tileAspect: CGFloat = 0.74
    static let plateRadius: CGFloat = 28
    static let grid = [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: gap)]
    /// A page a little darker than white behind the glass plates; near black in dark mode.
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.05, alpha: 1) : UIColor(white: 0.965, alpha: 1)
    })
    /// White in light mode, raised gray in dark mode: the tint of every plate's glass.
    static let plateTint = Color(uiColor: .secondarySystemGroupedBackground)
}

extension EnvironmentValues {
    /// The color plates are tinted toward; a reader background sets a lighter shade of itself.
    @Entry var plateTint: Color = Tokens.plateTint
}

extension View {
    /// The one surface of tiles, albums and text plates: Liquid Glass tinted toward the plate color.
    func plate(cornerRadius: CGFloat) -> some View {
        modifier(Plate(cornerRadius: cornerRadius))
    }
}

private struct Plate: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.plateTint) private var tint

    func body(content: Content) -> some View {
        content.glassEffect(.regular.tint(tint.opacity(0.85)), in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
