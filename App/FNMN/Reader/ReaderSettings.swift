import SwiftUI
import Textual

/// Three pages, each with a light and a dark shade that follow the system's appearance.
enum ReaderBackground: String, CaseIterable, Identifiable {
    case plain, gray, paper
    var id: String { rawValue }

    var name: String {
        switch self {
        case .plain: "Black & White"
        case .gray: "Gray"
        case .paper: "Paper"
        }
    }

    /// The page in light and in dark. Only the page is chosen; its plates and links follow from it (`PageColors`).
    private var page: (light: UIColor, dark: UIColor) {
        switch self {
        case .plain: (UIColor(white: 1, alpha: 1), UIColor(white: 0, alpha: 1))
        case .gray: (UIColor(white: 0.88, alpha: 1), UIColor(white: 0.17, alpha: 1))
        case .paper: (UIColor(red: 0.95, green: 0.915, blue: 0.84, alpha: 1), UIColor(red: 0.18, green: 0.15, blue: 0.11, alpha: 1))
        }
    }

    var canvas: Color {
        Self.adaptive(light: page.light, dark: page.dark)
    }

    var plate: Color {
        Self.adaptive(light: PageColors.plate(on: page.light, dark: false), dark: PageColors.plate(on: page.dark, dark: true))
    }

    /// A swatch drawn as an image, so the menu shows the color itself instead of tinting a template:
    /// the page in light on the left half, in dark on the right.
    var swatch: Image {
        let size = CGSize(width: 22, height: 22)
        let page = UIColor(canvas)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let circle = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            page.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).setFill()
            context.cgContext.fillEllipse(in: circle)
            page.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).setFill()
            context.cgContext.addArc(center: CGPoint(x: 11, y: 11), radius: 10, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            context.cgContext.fillPath()
            UIColor.separator.setStroke()
            context.cgContext.setLineWidth(1)
            context.cgContext.strokeEllipse(in: circle)
        }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }

    /// The color of links and of the buttons that act like links: the accent on the black and white page, a
    /// shade of the page on the others; links are underlined as well.
    var link: Color {
        guard self != .plain else { return .accentColor }
        return Self.adaptive(
            light: PageColors.link(on: page.light, dark: false),
            dark: PageColors.link(on: page.dark, dark: true)
        )
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// The plate and link colors of a page. A plate stands apart from its page by lightness: lighter while the page
/// leaves room above it, darker on a white page, and lighter in the dark. A link takes the page's hue at full color,
/// or stays gray on a gray page, and is as dark, or in the dark as light, as reading it on the plate needs: a
/// contrast of 4.5 to 1.
enum PageColors {
    static func plate(on page: UIColor, dark: Bool) -> UIColor {
        if dark { return page.mixed(with: .white, by: 0.12) }
        return page.luminance > 0.95 ? page.mixed(with: .black, by: 0.05) : page.mixed(with: .white, by: 0.35)
    }

    static func link(on page: UIColor, dark: Bool) -> UIColor {
        let plate = plate(on: page, dark: dark)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        page.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let color: CGFloat = saturation > 0.02 ? (dark ? 0.5 : 0.9) : 0
        let brightnesses = stride(from: 0.0, through: 1.0, by: 0.01).map { CGFloat(dark ? $0 : 1 - $0) }
        return brightnesses.lazy
            .map { UIColor(hue: hue, saturation: color, brightness: $0, alpha: 1) }
            .first { $0.contrast(with: plate) >= 4.5 } ?? (dark ? .white : .black)
    }
}

private extension UIColor {
    var rgb: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue)
    }

    func mixed(with other: UIColor, by share: CGFloat) -> UIColor {
        let (a, b) = (rgb, other.rgb)
        return UIColor(
            red: a.red + (b.red - a.red) * share,
            green: a.green + (b.green - a.green) * share,
            blue: a.blue + (b.blue - a.blue) * share,
            alpha: 1
        )
    }

    /// The relative luminance of WCAG: the share of light the eye sees in the color, from 0 for black to 1 for white.
    var luminance: CGFloat {
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (red, green, blue) = rgb
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(with other: UIColor) -> CGFloat {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

enum ReaderFont: String, CaseIterable, Identifiable {
    case system, serif
    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "San Francisco"
        case .serif: "New York"
        }
    }

    var design: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        }
    }
}

enum ReaderAppearance {
    static let typeSizeKey = "readerTypeSize"
    static let backgroundKey = "readerBackground"
    static let fontKey = "readerFont"
    static let lineKey = "readerLine"
    static let sizes: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]
    static let defaultSize = 3
}

/// Text size, background and font, the same three choices for every screen that reads text.
struct ReaderAppearanceControls: View {
    @AppStorage(ReaderAppearance.typeSizeKey) private var size = ReaderAppearance.defaultSize
    @AppStorage(ReaderAppearance.backgroundKey) private var background = ReaderBackground.plain
    @AppStorage(ReaderAppearance.fontKey) private var font = ReaderFont.system

    var body: some View {
        ControlGroup {
            Button("Smaller", systemImage: "textformat.size.smaller") { size -= 1 }
                .disabled(size <= 0)
            Button("Larger", systemImage: "textformat.size.larger") { size += 1 }
                .disabled(size >= ReaderAppearance.sizes.count - 1)
        }
        Picker("Background", selection: $background) {
            ForEach(ReaderBackground.allCases) { option in
                Label { Text(option.name) } icon: { option.swatch }
                    .tag(option)
            }
        }
        .pickerStyle(.palette)
        Picker(selection: $font) {
            ForEach(ReaderFont.allCases) { option in
                Text(option.name).tag(option)
            }
        } label: {
            Label("Font", systemImage: "textformat")
            Text(font.name)
        }
        .pickerStyle(.menu)
    }
}

/// The reader's one `···` button: text size and background right inside the menu, the reading line, and the original.
struct ReaderMenu: View {
    let reader: ReaderCoordinator
    let page: URL?
    @AppStorage(ReaderAppearance.lineKey) private var showsLine = false

    var body: some View {
        Menu("Reading Options", systemImage: "ellipsis") {
            ReaderAppearanceControls()
            Toggle("Reading Line", systemImage: "ruler",isOn: $showsLine)
            let lowest = reader.document.lowestHeadings
            if !lowest.isEmpty {
                if lowest.isSubset(of: reader.state.folded) {
                    Button("Expand All", systemImage: "arrow.up.left.and.arrow.down.right") { reader.send(.foldAll(false)) }
                } else {
                    Button("Collapse All", systemImage: "arrow.down.right.and.arrow.up.left") { reader.send(.foldAll(true)) }
                }
            }
            OpenOriginalButton(itemID: reader.materialID, page: page)
        }
    }
}

/// Applies the chosen text size and background to a reader.
struct ReaderAppearanceModifier: ViewModifier {
    @AppStorage(ReaderAppearance.typeSizeKey) private var size = ReaderAppearance.defaultSize
    @AppStorage(ReaderAppearance.backgroundKey) private var background = ReaderBackground.plain
    @AppStorage(ReaderAppearance.fontKey) private var font = ReaderFont.system

    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(ReaderAppearance.sizes[min(max(size, 0), ReaderAppearance.sizes.count - 1)])
            // A font, not a font design: Textual derives code from the environment font with `.monospaced()`.
            .font(.system(.body, design: font.design))
            .background(background.canvas)
            .environment(\.plateTint, background.plate)
            // Only links take the page's link color; a tint would also paint every icon of the reader's menus.
            .textual.inlineStyle(.default.link(.foregroundColor(background.link), .underlineStyle(.single)))
    }
}
