import SwiftUI
import UIKit

struct HorizontalPan: UIGestureRecognizerRepresentable {
    var starts: (_ translation: CGFloat) -> Bool = { _ in true }
    var changed: (CGFloat) -> Void
    var ended: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.starts = starts
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            changed(translation)
        case .ended:
            ended(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            ended(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var starts: (CGFloat) -> Bool = { _ in true }
        private static let backEdge: CGFloat = 24

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let moved = pan.translation(in: view)
            guard abs(moved.x) > abs(moved.y), starts(moved.x) else { return false }
            if moved.x > 0, pan.location(in: view.window).x - moved.x < Self.backEdge { return false }
            var touched = view.hitTest(pan.location(in: view), with: nil)
            while let current = touched, current !== view {
                if let scroll = current as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 1 { return false }
                touched = current.superview
            }
            return true
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other.view is UIScrollView)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard other is UIPanGestureRecognizer else { return false }
            guard let scroll = other.view as? UIScrollView else { return true }
            return other !== scroll.panGestureRecognizer
        }
    }
}
