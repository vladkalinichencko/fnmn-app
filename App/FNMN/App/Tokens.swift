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
    /// The height of a plate for something set in the text whose own height is not known until it loads.
    static let embedHeight: CGFloat = 180
    /// How strongly read text shows: a read paragraph, a read heading and the text above the reading line alike.
    static let readOpacity = 0.6
    static let grid = [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: gap)]
    /// A page a little darker than white behind the glass plates; near black in dark mode.
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.05, alpha: 1) : UIColor(white: 0.965, alpha: 1)
    })
    /// White in light mode, raised gray in dark mode: the tint of every plate's glass.
    static let plateTint = Color(uiColor: .secondarySystemGroupedBackground)
    /// The title of a screen's section: Continue, Unsorted, Albums, Annotations, Archive.
    static let sectionTitle = Font.title.bold()

    /// How many columns of annotation cards a width holds: one on a phone, two on a tablet upright, four lying down.
    /// A card is never narrower than about 270 points nor wider than about 600.
    static func annotationColumns(forWidth width: CGFloat) -> Int {
        switch width {
        case ..<640: 1
        case ..<1100: 2
        default: 4
        }
    }

    /// The width of the column a text is read in: 60% of a wide screen, centered, but never narrower than
    /// `minReading`, and the whole width where the screen is no wider than that.
    static let readingFraction: CGFloat = 0.6
    static let minReading: CGFloat = 560
    static func readingWidth(in width: CGFloat) -> CGFloat {
        min(width, max(width * readingFraction, minReading))
    }

    /// The radius of a shape set `inset` inside one of radius `outer`, so both curves share a center.
    static func concentric(_ outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(outer - inset, 0)
    }

    /// The glass caption of a picture tile, inset from the tile's edges.
    static let captionInset: CGFloat = 8
    static var captionRadius: CGFloat { concentric(tileRadius, inset: captionInset) }
    /// A code block inside a paragraph plate, whose text starts `tilePadding` in.
    static var codeRadius: CGFloat { concentric(plateRadius, inset: tilePadding) }
}

/// A rounded rectangle turned and scaled about its anchor, the center unless told otherwise, and moved. Glass under
/// `rotationEffect` or `scaleEffect` draws past its own frame, so a turned plate keeps its view still and turns its
/// glass's shape.
struct TurnedRectangle: Shape {
    let cornerRadius: CGFloat
    var degrees: Double = 0
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: rect)
            .applying(
                CGAffineTransform(translationX: rect.midX + offset.width, y: rect.midY + offset.height)
                    .rotated(by: degrees * .pi / 180)
                    .scaledBy(x: scale, y: scale)
                    .translatedBy(x: -rect.midX, y: -rect.midY)
            )
    }
}

extension EnvironmentValues {
    /// The color plates are tinted toward; a reader background sets a lighter shade of itself.
    @Entry var plateTint: Color = Tokens.plateTint
}

extension View {
    /// The one surface of tiles, albums and text plates: Liquid Glass tinted toward the plate color.
    func plate(cornerRadius: CGFloat) -> some View {
        plate(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// A plate of any shape; a turned plate passes a turned shape, since glass under a rotation draws past its frame.
    func plate(in shape: some Shape) -> some View {
        modifier(Plate(shape: shape))
    }
}

private struct Plate<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.plateTint) private var tint

    /// Glass shows its tint faintly, whitening it in the light and losing it over a black page, so the plate color
    /// also lies under the text and the plate keeps the color worked out for its page.
    func body(content: Content) -> some View {
        content
            .background { shape.fill(tint.opacity(0.7)) }
            .glassEffect(.regular.tint(tint.opacity(0.85)), in: shape)
    }
}

/// Every spinner in the app is gray: the tint is the color of links and of reading progress, and waiting is neither.
struct GraySpinner: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        ProgressView(configuration).tint(.secondary)
    }
}

/// The one thing shown while anything loads, whatever it is: the system spinner with no words, in the middle of the
/// space it is given. A screen shows it on its page; something set in the text, a video, a picture or an
/// interactive figure, stands on its glass plate, and the spinner turns on that plate until the thing covers it.
struct Loading: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
