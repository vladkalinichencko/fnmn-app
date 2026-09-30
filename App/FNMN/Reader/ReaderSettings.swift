import SwiftUI

enum ReaderBackground: String, CaseIterable, Identifiable {
    case system, paper, gray, night
    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "Default"
        case .paper: "Paper"
        case .gray: "Gray"
        case .night: "Night"
        }
    }

    /// The page. Each background has a plate color that is the same hue with more white, or more light at night.
    var canvas: Color {
        switch self {
        case .system: Tokens.canvas
        case .paper: Color(red: 0.95, green: 0.915, blue: 0.84)
        case .gray: Color(white: 0.88)
        case .night: .black
        }
    }

    var plate: Color {
        switch self {
        case .system: Tokens.plateTint
        case .paper: Color(red: 0.995, green: 0.98, blue: 0.945)
        case .gray: Color(white: 0.965)
        case .night: Color(white: 0.14)
        }
    }

    /// A swatch drawn as an image, so the menu shows the color itself instead of tinting a template.
    var swatch: Image {
        let size = CGSize(width: 22, height: 22)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let circle = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            if self == .system {
                UIColor.white.setFill()
                context.cgContext.fillEllipse(in: circle)
                UIColor.black.setFill()
                context.cgContext.addArc(center: CGPoint(x: 11, y: 11), radius: 10, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
                context.cgContext.fillPath()
            } else {
                UIColor(canvas).setFill()
                context.cgContext.fillEllipse(in: circle)
            }
            UIColor.separator.setStroke()
            context.cgContext.setLineWidth(1)
            context.cgContext.strokeEllipse(in: circle)
        }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .paper, .gray: .light
        case .night: .dark
        }
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

/// The reader's one `···` button: text size and background right inside the menu, and the original.
struct ReaderMenu: View {
    let reader: ReaderCoordinator
    let page: URL?
    @AppStorage(ReaderAppearance.typeSizeKey) private var size = ReaderAppearance.defaultSize
    @AppStorage(ReaderAppearance.backgroundKey) private var background = ReaderBackground.system
    @AppStorage(ReaderAppearance.fontKey) private var font = ReaderFont.system

    var body: some View {
        Menu("Reading Options", systemImage: "ellipsis") {
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
    @AppStorage(ReaderAppearance.backgroundKey) private var background = ReaderBackground.system
    @AppStorage(ReaderAppearance.fontKey) private var font = ReaderFont.system

    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(ReaderAppearance.sizes[min(max(size, 0), ReaderAppearance.sizes.count - 1)])
            // A font, not a font design: Textual derives code from the environment font with `.monospaced()`.
            .font(.system(.body, design: font.design))
            .background(background.canvas)
            .environment(\.plateTint, background.plate)
            .environment(\.colorScheme, background.scheme ?? colorScheme)
            // The bar's glass follows the window, not the environment above; without this a dark page
            // got light buttons, and a button's label and its glass disagreed on the scheme.
            .toolbarColorScheme(background.scheme, for: .navigationBar)
    }

    @Environment(\.colorScheme) private var colorScheme
}
