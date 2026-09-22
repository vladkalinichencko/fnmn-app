import SwiftUI
import UIKit

struct SelectableParagraph: UIViewRepresentable {
    var text: String
    var quotes: [String]
    var onHighlight: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHighlight: onHighlight)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onHighlight = onHighlight
        view.attributedText = marked(text, quotes: quotes)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(size.height, 1))
    }

    private func marked(_ text: String, quotes: [String]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ])
        for quote in quotes where !quote.isEmpty {
            var search = text.startIndex..<text.endIndex
            while let found = text.range(of: quote, range: search) {
                result.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.45), range: NSRange(found, in: text))
                search = found.upperBound..<text.endIndex
            }
        }
        return result
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onHighlight: (String) -> Void

        init(onHighlight: @escaping (String) -> Void) {
            self.onHighlight = onHighlight
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let text = textView.text, let swiftRange = Range(range, in: text) else {
                return UIMenu(children: suggestedActions)
            }
            let quote = String(text[swiftRange])
            let highlight = UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { [weak self] _ in
                self?.onHighlight(quote)
            }
            return UIMenu(children: [highlight] + suggestedActions)
        }
    }
}
