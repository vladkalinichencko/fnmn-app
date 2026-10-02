import FNMNCore
import UIKit
import UniformTypeIdentifiers

/// No screen: the link or PDF goes into the app group's inbox and the app opens over the sheet, which closes.
/// The app imports the inbox as soon as it is active.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private var didHandOff = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didHandOff else { return }
        didHandOff = true
        Task { await handOff() }
    }

    private func handOff() async {
        guard let inbox = CaptureInbox(), await dropFirstItem(into: inbox) else {
            showFailure()
            return
        }
        openApp()
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// An extension has no `UIApplication.shared`, and `extensionContext.open` is for other extension types; the
    /// application object is still on the responder chain, and it opens the app's own scheme.
    private func openApp() {
        guard let url = URL(string: "fnmn://inbox") else { return }
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = current.next
        }
    }

    private func dropFirstItem(into inbox: CaptureInbox) async -> Bool {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return false }
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                if await dropFile(of: provider, as: UTType.pdf, into: inbox) { return true }
            } else if provider.canLoadObject(ofClass: URL.self), let url = await url(from: provider) {
                if url.isFileURL {
                    if (try? inbox.drop(file: url)) != nil { return true }
                } else if ["http", "https"].contains(url.scheme?.lowercased()) {
                    if (try? inbox.drop(link: url)) != nil { return true }
                }
            }
        }
        return false
    }

    private func dropFile(of provider: NSItemProvider, as type: UTType, into inbox: CaptureInbox) async -> Bool {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                // The file is deleted when this handler returns, so it is copied in here.
                continuation.resume(returning: url.flatMap { try? inbox.drop(file: $0) } != nil)
            }
        }
    }

    private func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                continuation.resume(returning: object)
            }
        }
    }

    private func showFailure() {
        let label = UILabel()
        label.text = "FNMN could not read this."
        label.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        Task {
            try? await Task.sleep(for: .seconds(2))
            extensionContext?.cancelRequest(withError: CocoaError(.fileReadUnknown))
        }
    }
}
