import SwiftUI

enum Tokens {
    static let gutter: CGFloat = 16
    static let gap: CGFloat = 14
    static let sectionGap: CGFloat = 28
    static let tileRadius: CGFloat = 38
    static let tilePadding: CGFloat = 16
    static let tileAspect: CGFloat = 0.74
    static let plateRadius: CGFloat = 28
    static let embedHeight: CGFloat = 180
    static let readOpacity = 0.6
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.05, alpha: 1) : UIColor(white: 0.965, alpha: 1)
    })
    static let plateTint = Color(uiColor: .secondarySystemGroupedBackground)
    static let sectionTitle = Font.title.bold()

    static let readingFraction: CGFloat = 0.6
    static let minReading: CGFloat = 560
    static func readingWidth(in width: CGFloat) -> CGFloat {
        min(width, max(width * readingFraction, minReading))
    }

    static func concentric(_ outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(outer - inset, 0)
    }

    static let captionInset: CGFloat = 8
    static var captionRadius: CGFloat { concentric(tileRadius, inset: captionInset) }
    static var codeRadius: CGFloat { concentric(plateRadius, inset: tilePadding) }
}

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
    @Entry var plateTint: Color = Tokens.plateTint
}

extension View {
    func plate(cornerRadius: CGFloat) -> some View {
        plate(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func plate(in shape: some Shape) -> some View {
        modifier(Plate(shape: shape))
    }
}

private struct Plate<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.plateTint) private var tint

    func body(content: Content) -> some View {
        content
            .background { shape.fill(tint.opacity(0.7)) }
            .glassEffect(.regular.tint(tint.opacity(0.85)), in: shape)
    }
}

struct GraySpinner: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        ProgressView(configuration).tint(.secondary)
    }
}

struct Loading: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
