import UIKit

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private var didHandOff = false
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "Opening FNMN"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didHandOff else { return }
        didHandOff = true
        Task { await handOff() }
    }

    private func handOff() async {
        guard let shared = await firstSharedURL(), let link = CaptureHandoff.link(for: shared), let context = extensionContext else {
            label.text = "FNMN could not read that link."
            return
        }
        let opened = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            context.open(link) { success in
                continuation.resume(returning: success)
            }
        }
        if opened {
            context.completeRequest(returningItems: nil)
        } else {
            label.text = "Open FNMN to add this link."
        }
    }

    private func firstSharedURL() async -> URL? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        for item in items {
            for provider in item.attachments ?? [] {
                if let url = await url(from: provider) { return url }
            }
        }
        return nil
    }

    private func url(from provider: NSItemProvider) async -> URL? {
        guard provider.canLoadObject(ofClass: URL.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                continuation.resume(returning: object)
            }
        }
    }
}
