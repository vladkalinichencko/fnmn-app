import SwiftUI
import UIKit

enum ReaderTypeSize: Int, CaseIterable, Identifiable {
    case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .xSmall: "Extra Small"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .xLarge: "Extra Large"
        case .xxLarge: "Extra Extra Large"
        case .xxxLarge: "Extra Extra Extra Large"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .xSmall: .xSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .xLarge
        case .xxLarge: .xxLarge
        case .xxxLarge: .xxxLarge
        }
    }
}

struct ReaderSettingsForm: View {
    @AppStorage("readerTypeSize") private var typeSize = ReaderTypeSize.large.rawValue
    @AppStorage("readerUsesBackground") private var usesBackground = false
    @AppStorage("readerBackgroundHex") private var backgroundHex = "FFFFFF"
    @State private var color = Color.white

    var body: some View {
        NavigationStack {
            Form {
                Picker("Text Size", selection: $typeSize) {
                    ForEach(ReaderTypeSize.allCases) { size in
                        Text(size.label).tag(size.rawValue)
                    }
                }
                Toggle("Background", isOn: $usesBackground)
                if usesBackground {
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                }
            }
            .navigationTitle("Text")
            .onAppear { color = Color(hex: backgroundHex) ?? .white }
            .onChange(of: color) { _, color in
                backgroundHex = color.hex
            }
        }
    }
}

enum ReaderAppearance {
    static var typeSize: DynamicTypeSize {
        let stored = UserDefaults.standard.object(forKey: "readerTypeSize") as? Int ?? ReaderTypeSize.large.rawValue
        return ReaderTypeSize(rawValue: stored)?.dynamicTypeSize ?? .large
    }

    static var background: Color? {
        guard UserDefaults.standard.bool(forKey: "readerUsesBackground") else { return nil }
        return Color(hex: UserDefaults.standard.string(forKey: "readerBackgroundHex") ?? "")
    }
}

private extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    var hex: String {
        let resolved = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
