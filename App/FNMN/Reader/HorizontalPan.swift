import SwiftUI
import UIKit

/// A pan that starts only when the finger moves sideways, so vertical scrolling passes straight through it.
/// `starts` gets the sideways distance the finger has gone and can leave one direction to the system's swipe actions.
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
        // Taken over by the system, for a scroll or a menu: as if the finger had not moved.
        case .cancelled, .failed:
            ended(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var starts: (CGFloat) -> Bool = { _ in true }
        private static let backEdge: CGFloat = 24

        /// A formula that scrolls sideways keeps the finger for itself, and so does the screen's left edge, where a
        /// rightward pan is the navigation stack's swipe back.
        /// The direction is read off how far the finger has gone, not how fast: a finger that lingers before it moves,
        /// or drags slowly, has a speed too small and uncertain to tell sideways from up, and the pan would fail
        /// for good while the page took the finger.
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

        /// Taps, presses and the pinch run alongside; anything a scroll view owns, the page's scrolling, does not.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other.view is UIScrollView)
        }

        /// Every other sideways pan waits until this one declines, the navigation stack's swipe back among them, so
        /// a finger that moves a plate never also leaves the screen. Only scrolling itself does not wait.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard other is UIPanGestureRecognizer else { return false }
            guard let scroll = other.view as? UIScrollView else { return true }
            return other !== scroll.panGestureRecognizer
        }
    }
}
