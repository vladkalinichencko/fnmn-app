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

    /// The page. Each background has a plate color that is the same hue with more white, or more light in the dark.
    var canvas: Color {
        switch self {
        case .plain: Self.adaptive(light: UIColor(white: 1, alpha: 1), dark: UIColor(white: 0, alpha: 1))
        case .gray: Self.adaptive(light: UIColor(white: 0.88, alpha: 1), dark: UIColor(white: 0.11, alpha: 1))
        case .paper: Self.adaptive(light: UIColor(red: 0.95, green: 0.915, blue: 0.84, alpha: 1),
                                   dark: UIColor(red: 0.11, green: 0.095, blue: 0.07, alpha: 1))
        }
    }

    var plate: Color {
        switch self {
        case .plain: Self.adaptive(light: UIColor(white: 0.95, alpha: 1), dark: UIColor(white: 0.14, alpha: 1))
        case .gray: Self.adaptive(light: UIColor(white: 0.965, alpha: 1), dark: UIColor(white: 0.19, alpha: 1))
        case .paper: Self.adaptive(light: UIColor(red: 0.995, green: 0.98, blue: 0.945, alpha: 1),
                                   dark: UIColor(red: 0.19, green: 0.17, blue: 0.13, alpha: 1))
        }
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
        switch self {
        case .plain: .accentColor
        case .gray: Self.adaptive(light: UIColor(white: 0.38, alpha: 1), dark: UIColor(white: 0.7, alpha: 1))
        case .paper: Self.adaptive(light: UIColor(red: 0.78, green: 0.36, blue: 0.04, alpha: 1),
                                   dark: UIColor(red: 0.95, green: 0.76, blue: 0.46, alpha: 1))
        }
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
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

/// The reader's one `···` button: text size and background right inside the menu, and the original.
struct ReaderMenu: View {
    let reader: ReaderCoordinator
    let page: URL?

    var body: some View {
        Menu("Reading Options", systemImage: "ellipsis") {
            ReaderAppearanceControls()
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
            .tint(background.link)
            // `Color.accentColor` ignores `.tint`, and Textual paints links with it, so the color is given outright.
            .textual.inlineStyle(.default.link(.foregroundColor(background.link), .underlineStyle(.single)))
    }
}
