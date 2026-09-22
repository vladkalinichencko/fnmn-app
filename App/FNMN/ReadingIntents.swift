import AppIntents
import UIKit

struct ContinueReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Reading"
    static let description = IntentDescription("Open the material you were last reading in FNMN.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let url = URL(string: "fnmn://continue") else { return .result() }
        await UIApplication.shared.open(url)
        return .result()
    }
}

struct AddLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Link to FNMN"
    static let description = IntentDescription("Open FNMN’s add sheet with a link ready to import.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Link")
    var link: URL

    init() {}

    init(link: URL) {
        self.link = link
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let handoff = CaptureHandoff.link(for: link) else { return .result() }
        await UIApplication.shared.open(handoff)
        return .result()
    }
}

struct AskAboutSelectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask About This Passage"
    static let description = IntentDescription("Send the passage last selected in FNMN to ChatGPT.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let stored = UserDefaults.standard.string(forKey: ChatGPTHandoff.passageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !stored.isEmpty else {
            throw NoPassageError()
        }

        if let parts = Self.splitPrompt(stored) {
            ChatGPTHandoff.copyAndOpen(title: parts.title, passage: parts.passage)
        } else {
            UIPasteboard.general.string = stored
            if let url = ChatGPTHandoff.destination(for: stored), UIApplication.shared.canOpenURL(url) {
                await UIApplication.shared.open(url)
            }
        }

        return .result(dialog: "Opening ChatGPT with your passage.")
    }

    private static func splitPrompt(_ stored: String) -> (title: String, passage: String)? {
        let prefix = ChatGPTHandoff.instruction + "\n\n"
        guard stored.hasPrefix(prefix) else { return nil }
        let rest = String(stored.dropFirst(prefix.count))
        guard let separator = rest.range(of: "\n\n") else { return nil }
        let title = String(rest[..<separator.lowerBound])
        let passage = String(rest[separator.upperBound...])
        guard !title.isEmpty, !passage.isEmpty else { return nil }
        return (title, passage)
    }
}

private struct NoPassageError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Select a passage in FNMN first, then try again."
    }
}

struct ReadingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueReadingIntent(),
            phrases: [
                "Continue reading in \(.applicationName)"
            ],
            shortTitle: "Continue Reading",
            systemImageName: "book"
        )

        AppShortcut(
            intent: AddLinkIntent(),
            phrases: [
                "Add this link to \(.applicationName)"
            ],
            shortTitle: "Add Link",
            systemImageName: "link"
        )

        AppShortcut(
            intent: AskAboutSelectionIntent(),
            phrases: [
                "Ask about this passage in \(.applicationName)"
            ],
            shortTitle: "Ask About Passage",
            systemImageName: "text.bubble"
        )
    }
}
