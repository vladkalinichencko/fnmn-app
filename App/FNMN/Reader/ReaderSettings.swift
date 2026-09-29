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

    var color: Color? {
        switch self {
        case .system: nil
        case .paper: Color(red: 0.97, green: 0.94, blue: 0.87)
        case .gray: Color(white: 0.9)
        case .night: .black
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .paper, .gray: .light
        case .night: .dark
        }
    }
}

enum ReaderAppearance {
    static let typeSizeKey = "readerTypeSize"
    static let backgroundKey = "readerBackground"
    static let sizes: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]
    static let defaultSize = 3
}

/// The reader's one `···` button: text size and background right inside the menu, and the original page.
struct ReaderMenu: View {
    let sourceURL: URL?
    @AppStorage(ReaderAppearance.typeSizeKey) private var size = ReaderAppearance.defaultSize
    @AppStorage(ReaderAppearance.backgroundKey) private var background = ReaderBackground.system

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
                    Label(option.name, systemImage: option == .system ? "circle.lefthalf.filled" : "circle.fill")
                        .tint(option.color ?? .primary)
                        .tag(option)
                }
            }
            .pickerStyle(.palette)
            if let sourceURL {
                Link(destination: sourceURL) { Label("Open Original", systemImage: "arrow.up.right") }
            }
        }
    }
}

/// Applies the chosen text size and background to a reader.
struct ReaderAppearanceModifier: ViewModifier {
    @AppStorage(ReaderAppearance.typeSizeKey) private var size = ReaderAppearance.defaultSize
    @AppStorage(ReaderAppearance.backgroundKey) private var background = ReaderBackground.system

    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(ReaderAppearance.sizes[min(max(size, 0), ReaderAppearance.sizes.count - 1)])
            .background(background.color ?? .clear)
            .environment(\.colorScheme, background.scheme ?? colorScheme)
    }

    @Environment(\.colorScheme) private var colorScheme
}
