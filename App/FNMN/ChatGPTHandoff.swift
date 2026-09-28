import UIKit

enum ChatGPTHandoff {
    static let instruction = "Explain this passage. Keep the formulas."
    static let passageKey = "fnmn.lastPrompt"

    static func prompt(title: String, passage: String) -> String {
        "\(instruction)\n\n\(title)\n\n\(passage)"
    }

    @MainActor
    static func remember(title: String, passage: String) -> String {
        let text = prompt(title: title, passage: passage)
        UIPasteboard.general.string = text
        UserDefaults.standard.set(text, forKey: passageKey)
        return text
    }

    @MainActor
    static func copyAndOpen(title: String, passage: String) {
        let text = remember(title: title, passage: passage)
        guard let url = destination(for: text) else { return }
        UIApplication.shared.open(url)
    }

    static func destination(for prompt: String) -> URL? {
        guard prompt.utf8.count < 1800 else { return URL(string: "chatgpt://") }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))
        guard let query = prompt.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return URL(string: "chatgpt://")
        }
        return URL(string: "https://chatgpt.com/?q=\(query)")
    }
}
