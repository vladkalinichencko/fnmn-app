import SwiftUI
import UIKit

/// A pan that starts only when the finger moves sideways, so vertical scrolling passes straight through it.
/// `starts` gets the sideways speed and can leave one direction to the system's swipe actions.
struct HorizontalPan: UIGestureRecognizerRepresentable {
    var starts: (_ velocity: CGFloat) -> Bool = { _ in true }
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

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.5 && starts(velocity.x)
        }

        /// The system's swipe actions watch the same plate; they have nothing on the side this pan takes, so both may run.
        /// Only the page's own scrolling stays exclusive.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other.view is UIScrollView)
        }

        /// Another sideways pan on the plate, the system's swipe among them, starts only once this one has declined,
        /// so the plate never moves under two gestures at once. Scrolling, taps and presses do not wait.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && !(other.view is UIScrollView)
        }
    }
}
