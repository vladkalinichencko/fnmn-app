import FNMNCore
import SwiftUI
import Textual

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

    func font(_ style: Font.TextStyle) -> Font {
        guard let face else { return .system(style, design: design) }
        return .custom(face, size: Self.defaultSize(of: style), relativeTo: style)
    }

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

struct ReaderAppearanceControls: View {
    var showsColumn = true
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
        if showsColumn {
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
}

struct ReaderMenu: View {
    let reader: ReaderCoordinator
    let page: URL?
    @AppStorage(ReaderAppearance.lineKey) private var showsLine = false
    @AppStorage(ReaderAppearance.wordStartsKey) private var boldsWordStarts = false

    private enum ReadingMode: Hashable {
        case column, posts, fast
    }

    var body: some View {
        Menu("Reading Options", systemImage: "ellipsis") {
            Picker("Reading Mode", selection: mode) {
                Text("Reader").tag(ReadingMode.column)
                Text("Posts").tag(ReadingMode.posts)
                Text("Fast").tag(ReadingMode.fast)
            }
            .pickerStyle(.segmented)
            ReaderAppearanceControls()
            Toggle("Reading Line", systemImage: "ruler",isOn: $showsLine)
            Toggle("Bold Word Starts", systemImage: "bold", isOn: $boldsWordStarts)
            Button("Find in Text", systemImage: "magnifyingglass") {
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

    private var mode: Binding<ReadingMode> {
        Binding(
            get: {
                if reader.state.shownPlate != nil {
                    return .posts
                }
                if reader.state.speedStart != nil {
                    return .fast
                }
                return .column
            },
            set: { mode in
                switch mode {
                case .column:
                    if reader.state.shownPlate != nil {
                        reader.send(.onePlate(false))
                    }
                    if reader.state.speedStart != nil {
                        reader.send(.speedReading(false))
                    }
                case .posts:
                    reader.send(.speedReading(false))
                    reader.send(.onePlate(true))
                case .fast:
                    reader.send(.speedReading(true))
                }
            }
        )
    }
}

struct ReaderAppearanceModifier: ViewModifier {
    @AppStorage(ReaderAppearance.typeSizeKey) private var size = ReaderAppearance.defaultSize
    @AppStorage(ReaderAppearance.backgroundKey) private var background = ReaderBackground.plain
    @AppStorage(ReaderAppearance.fontKey) private var font = ReaderFont.system
    @AppStorage(ReaderAppearance.lineSpacingKey) private var spacing = ReaderLineSpacing.regular

    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(ReaderAppearance.sizes[min(max(size, 0), ReaderAppearance.sizes.count - 1)])
            .font(font.font(.body))
            .textual.paragraphStyle(ReaderParagraph(lineSpacing: spacing.share))
            .background(background.canvas)
            .environment(\.plateTint, background.plate)
            .textual.inlineStyle(.default.link(.foregroundColor(background.link), .underlineStyle(.single)))
            .onChange(of: size) { _, value in
                let resolved = ReaderAppearance.sizes[min(max(value, 0), ReaderAppearance.sizes.count - 1)]
                print("ReaderAppearance size \(value) → \(resolved)")
            }
    }
}

private struct ReaderParagraph: StructuredText.ParagraphStyle {
    let lineSpacing: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(lineSpacing))
            .textual.blockSpacing(.fontScaled(top: 0.8))
    }
}
