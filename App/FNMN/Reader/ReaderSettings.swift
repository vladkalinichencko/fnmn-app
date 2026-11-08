import FNMNCore
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

/// The two system faces and three bundled ones. The bundled files carry their own Cyrillic, drawn in from a close
/// face (`server/fonts/build_reader_fonts.py`): CoreText's fallback for a missing glyph keeps neither bold nor italic.
enum ReaderFont: String, CaseIterable, Identifiable {
    case system, serif, libron, literata, atkinson
    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "San Francisco"
        case .serif: "New York"
        case .libron: "Libron"
        case .literata: "Literata"
        case .atkinson: "Atkinson Hyperlegible"
        }
    }

    /// The bundled face's regular style; SwiftUI's bold and italic find the family's other styles from it.
    private var face: String? {
        switch self {
        case .system, .serif: nil
        case .libron: "Libron-Regular"
        case .literata: "Literata-Regular"
        case .atkinson: "AtkinsonHyperlegibleNext-Regular"
        }
    }

    private var design: Font.Design {
        switch self {
        case .system, .atkinson: .default
        case .serif, .libron, .literata: .serif
        }
    }

    /// The face at a text style's size, growing with the reader's text size like the system's own fonts.
    func font(_ style: Font.TextStyle) -> Font {
        guard let face else { return .system(style, design: design) }
        return .custom(face, size: Self.defaultSize(of: style), relativeTo: style)
    }

    /// A text style's size at the default text size, which `relativeTo` scales from.
    private static func defaultSize(of style: Font.TextStyle) -> CGFloat {
        let platform: UIFont.TextStyle = switch style {
        case .extraLargeTitle2: .extraLargeTitle2
        case .extraLargeTitle: .extraLargeTitle
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
        return UIFont.preferredFont(forTextStyle: platform, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
    }
}

/// The room between lines of a paragraph, as a share of the font's size. More room helps an eye that loses its line.
enum ReaderLineSpacing: String, CaseIterable, Identifiable {
    case tight, regular, loose
    var id: String { rawValue }

    var name: String {
        switch self {
        case .tight: "Tight"
        case .regular: "Regular"
        case .loose: "Loose"
        }
    }

    var share: CGFloat {
        switch self {
        case .tight: 0.12
        case .regular: 0.23
        case .loose: 0.5
        }
    }
}

/// How wide the column of text is. A narrower column has shorter lines, which are easier to keep one's place in.
enum ReaderColumn: String, CaseIterable, Identifiable {
    case narrow, regular, wide
    var id: String { rawValue }

    var name: String {
        switch self {
        case .narrow: "Narrow"
        case .regular: "Regular"
        case .wide: "Wide"
        }
    }

    /// The column's width on a screen this wide: the regular one is `Tokens.readingWidth`, the narrow one a little
    /// under it even on a phone, the wide one most of a wide screen.
    func width(in screen: CGFloat) -> CGFloat {
        switch self {
        case .narrow: Tokens.readingWidth(in: screen) * 0.86
        case .regular: Tokens.readingWidth(in: screen)
        case .wide: min(screen, max(screen * 0.8, Tokens.minReading))
        }
    }
}

enum ReaderAppearance {
    static let typeSizeKey = "readerTypeSize"
    static let backgroundKey = "readerBackground"
    static let fontKey = "readerFont"
    static let lineSpacingKey = "readerLineSpacing"
    static let columnKey = "readerColumn"
    static let lineKey = "readerLine"
    static let lineSideKey = "readerLineSide"
    static let wordStartsKey = "readerWordStarts"
    /// The materials read one plate at a time, kept on this device only, like the rest of how the reader looks.
    static let onePlateKey = "readerOnePlate"
    static let speedKey = "readerSpeedWordsPerMinute"
    static let speedWordsKey = "readerSpeedWordsPerFrame"
    static let speedPausesKey = "readerSpeedPauses"

    enum SpeedSetting: String, CaseIterable {
        case wordsPerMinute = "readerSpeedWordsPerMinute"
        case wordsPerFrame = "readerSpeedWordsPerFrame"
        case pauses = "readerSpeedPauses"

        func key(_ kind: FNMNCore.Material.Kind) -> String {
            "\(rawValue).\(kind == .book ? "book" : "article")"
        }
    }

    static func makeSpeedProfiles(in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "readerSpeedProfiles") else {
            return
        }
        defaults.set(true, forKey: "readerSpeedProfiles")
        for kind in [FNMNCore.Material.Kind.article, .book] {
            for setting in SpeedSetting.allCases {
                guard let value = defaults.object(forKey: setting.rawValue) else {
                    continue
                }
                if setting == .pauses {
                    defaults.set(SpeedPauseProfile(legacy: value as? String).json, forKey: setting.key(kind))
                } else {
                    defaults.set(value, forKey: setting.key(kind))
                }
            }
        }
    }

    static let sizes: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]
    static let defaultSize = 3

    static func readsOnePlate(_ materialID: String) -> Bool {
        UserDefaults.standard.stringArray(forKey: onePlateKey)?.contains(materialID) == true
    }

    static func setReadsOnePlate(_ reads: Bool, materialID: String) {
        var materials = Set(UserDefaults.standard.stringArray(forKey: onePlateKey) ?? [])
        guard materials.contains(materialID) != reads else { return }
        if reads { materials.insert(materialID) } else { materials.remove(materialID) }
        UserDefaults.standard.set(materials.sorted(), forKey: onePlateKey)
    }
}

/// Text size, background, font, line spacing and column width, the same choices for every screen that reads text.
struct ReaderAppearanceControls: View {
    @AppStorage(ReaderAppearance.typeSizeKey) private var size = ReaderAppearance.defaultSize
    @AppStorage(ReaderAppearance.backgroundKey) private var background = ReaderBackground.plain
    @AppStorage(ReaderAppearance.fontKey) private var font = ReaderFont.system
    @AppStorage(ReaderAppearance.lineSpacingKey) private var spacing = ReaderLineSpacing.regular
    @AppStorage(ReaderAppearance.columnKey) private var column = ReaderColumn.regular

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
        Picker(selection: $spacing) {
            ForEach(ReaderLineSpacing.allCases) { option in
                Text(option.name).tag(option)
            }
        } label: {
            Label("Line Spacing", systemImage: "arrow.up.and.down.text.horizontal")
            Text(spacing.name)
        }
        .pickerStyle(.menu)
        Picker(selection: $column) {
            ForEach(ReaderColumn.allCases) { option in
                Text(option.name).tag(option)
            }
        } label: {
            Label("Column Width", systemImage: "arrow.left.and.right.text.vertical")
            Text(column.name)
        }
        .pickerStyle(.menu)
    }
}

/// The reader's one `···` button: text size and background right inside the menu, the reading line, and the original.
struct ReaderMenu: View {
    let reader: ReaderCoordinator
    let page: URL?
    @AppStorage(ReaderAppearance.lineKey) private var showsLine = false
    @AppStorage(ReaderAppearance.wordStartsKey) private var boldsWordStarts = false

    var body: some View {
        Menu("Reading Options", systemImage: "ellipsis") {
            ReaderAppearanceControls()
            Toggle("Reading Line", systemImage: "ruler",isOn: $showsLine)
            Toggle("Bold Word Starts", systemImage: "bold", isOn: $boldsWordStarts)
            Toggle("One Plate at a Time", systemImage: "rectangle.stack", isOn: Binding(
                get: { reader.state.shownPlate != nil },
                set: { reader.send(.onePlate($0)) }
            ))
            Button("Speed Reading", systemImage: "hare") { reader.send(.speedReading(true)) }
            if reader.state.spot == nil {
                Button("Spot Reading", systemImage: "text.cursor") { reader.send(.spot(true)) }
            } else {
                Button("Stop Spot Reading", systemImage: "xmark.circle") { reader.send(.spot(false)) }
            }
            Button("Find in Material", systemImage: "magnifyingglass") {
                if reader.state.shownPlate != nil {
                    reader.send(.onePlate(false))
                }
                reader.send(.find(true))
            }
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
    @AppStorage(ReaderAppearance.lineSpacingKey) private var spacing = ReaderLineSpacing.regular

    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(ReaderAppearance.sizes[min(max(size, 0), ReaderAppearance.sizes.count - 1)])
            // A font, not a font design: Textual derives code from the environment font with `.monospaced()`, which
            // turns a bundled face, having no fixed-width style, into the system's fixed-width font.
            .font(font.font(.body))
            .textual.paragraphStyle(ReaderParagraph(lineSpacing: spacing.share))
            .background(background.canvas)
            .environment(\.plateTint, background.plate)
            // Only links take the page's link color; a tint would also paint every icon of the reader's menus.
            .textual.inlineStyle(.default.link(.foregroundColor(background.link), .underlineStyle(.single)))
    }
}

/// Textual's paragraph with the reader's line spacing.
private struct ReaderParagraph: StructuredText.ParagraphStyle {
    let lineSpacing: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(lineSpacing))
            .textual.blockSpacing(.fontScaled(top: 0.8))
    }
}
