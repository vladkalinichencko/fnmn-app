import SwiftUI
import UIKit

func applyQuoteMarks(_ mutable: NSMutableAttributedString, marks: [ParagraphQuoteMark]) {
    let plain = mutable.string as NSString
    for item in marks where !item.quote.isEmpty {
        var location = 0
        while location < plain.length {
            let search = NSRange(location: location, length: plain.length - location)
            let found = plain.range(of: item.quote, options: [], range: search)
            guard found.location != NSNotFound else { break }
            switch item.mark {
            case .highlight:
                mutable.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.45), range: found)
            case .strikethrough:
                mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: found)
            }
            location = found.location + max(found.length, 1)
        }
    }
}

struct ParagraphQuoteMark: Equatable {
    var quote: String
    var mark: TextMark
}

struct SelectableParagraph: UIViewRepresentable {
    var text: String
    var marks: [ParagraphQuoteMark]
    var onSelectParagraph: () -> Void = {}
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
        context.coordinator.onSelectParagraph = onSelectParagraph
        view.attributedText = marked(text, marks: marks)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(size.height, 1))
    }

    private func marked(_ text: String, marks: [ParagraphQuoteMark]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ])
        applyQuoteMarks(result, marks: marks)
        return result
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onHighlight: (String) -> Void
        var onSelectParagraph: () -> Void = {}

        init(onHighlight: @escaping (String) -> Void) {
            self.onHighlight = onHighlight
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            let selectParagraph = UIAction(title: "Select paragraph", image: UIImage(systemName: "rectangle")) { [weak self] _ in
                self?.onSelectParagraph()
            }
            guard range.length > 0, let text = textView.text, let swiftRange = Range(range, in: text) else {
                return UIMenu(children: [selectParagraph] + suggestedActions)
            }
            let quote = String(text[swiftRange])
            let highlight = UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { [weak self] _ in
                self?.onHighlight(quote)
            }
            return UIMenu(children: [highlight] + suggestedActions)
        }
    }
}
