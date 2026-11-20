#if os(iOS)
import FentonAppleCore
import UIKit

/// Push and pop on a single-page layout (phone, a folded Duo, a portrait iPad) that move the way ``FentonColumnsViewController``
/// moves its columns: both pages travel a full width, the new one in from the trailing edge and the old one out by the leading
/// edge, with no dim, no shadow and no fade. Back reverses it, and an edge swipe scrubs it. **Opt-in**: a navigation controller
/// keeps UIKit's own transition and swipe until an app creates one of these for it (and keeps a reference, because the
/// navigation controller holds its delegate weakly).
///
/// ```swift
/// let navigation = FentonNavigationController(rootViewController: home)
/// let motion = FentonStackMotion(navigation: navigation, reduceMotion: { environment.reduceMotion })
/// navigation.delegate = motion      // or forward the three delegate methods below from the app's own delegate
/// ```
///
/// Three parts: a transition (one push or pop, built on a `UIViewPropertyAnimator` so the interactive pop can scrub it), an
/// interaction (the `UIPercentDrivenInteractiveTransition` the swipe drives: completes past half or on a flick, otherwise the
/// animator reverses), and the edge pan, which replaces the system's `interactivePopGestureRecognizer` (and on iOS 26 its content
/// swipe) so the swipe is the same on every OS and pops through `popViewController(animated:)`, where a ``FentonNavigationController``
/// admits it.
///
/// **Reduce Motion** turns the slide into a cross-fade over ``FentonMotion/quick``; the swipe still pops and scrubs the fade.
@MainActor
public final class FentonStackMotion: NSObject, UIGestureRecognizerDelegate, UINavigationControllerDelegate {
    // MARK: - Properties

    private weak var navigation: UINavigationController?
    private let motion: FentonMotion
    private let reduceMotion: () -> Bool
    private let isEnabled: () -> Bool
    private let announceScreenChange: () -> Void
    private let pan = UIScreenEdgePanGestureRecognizer()
    private var interaction: FentonStackInteraction?

    /// How far the finger has to go, as a fraction of the width, for a let-go to complete.
    public static let completionFraction: CGFloat = 0.5
    /// The speed in points per second toward the trailing edge that completes a let-go regardless of distance.
    public static let completionVelocity: CGFloat = 600

    // MARK: - Creating

    /// Installs the edge swipe on `navigation`'s view and turns the system swipes off.
    /// - Parameters:
    ///   - navigation: The stack to move.
    ///   - motion: The spring and the cross-fade duration.
    ///   - reduceMotion: Reduce Motion, read when a transition starts (pass `{ environment.reduceMotion }`).
    ///   - isEnabled: False while something else shows the stack's routes (the columns of a wide window): no animation controller
    ///     is returned and the swipe does not begin.
    ///   - announceScreenChange: Tells VoiceOver the screen changed once an animated push or pop has landed; the custom transition
    ///     replaces the system's, which would have done it.
    public init(navigation: UINavigationController, motion: FentonMotion = FentonMotion(),
                reduceMotion: @escaping () -> Bool, isEnabled: @escaping () -> Bool = { true },
                announceScreenChange: @escaping () -> Void = { FentonAnnouncer.screenChanged() }) {
        self.navigation = navigation
        self.motion = motion
        self.reduceMotion = reduceMotion
        self.isEnabled = isEnabled
        self.announceScreenChange = announceScreenChange
        super.init()
        pan.edges = navigation.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        pan.delegate = self
        pan.addTarget(self, action: #selector(panned(_:)))
        pan.name = "FentonStackMotion.edgePan"
        navigation.view.addGestureRecognizer(pan)
        silenceSystemGestures()
    }

    /// The system's edge pop and the iOS 26 content pop stay off: the edge pan pops through the animator. UIKit re-enables the
    /// first when the stack changes, so this runs after every transition too.
    public func silenceSystemGestures() {
        navigation?.interactivePopGestureRecognizer?.isEnabled = false
        if #available(iOS 26.0, *) { navigation?.interactiveContentPopGestureRecognizer?.isEnabled = false }
    }

    /// The edge pan that drives the swipe back.
    public var edgePanRecognizer: UIScreenEdgePanGestureRecognizer { pan }

    /// Whether a swipe is in progress.
    public var isSwiping: Bool { interaction != nil }

    // MARK: - Navigation controller delegate

    // The pieces of `UINavigationControllerDelegate` this type owns. A stack whose controller is its own delegate forwards these; a
    // plain one sets this object as its delegate.

    public func navigationController(_ navigationController: UINavigationController,
                                     animationControllerFor operation: UINavigationController.Operation,
                                     from fromVC: UIViewController,
                                     to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        guard isEnabled(), operation != .none else { return nil }
        return FentonStackTransition(isPush: operation == .push, isInteractive: interaction != nil,
                                     rightToLeft: navigationController.view.effectiveUserInterfaceLayoutDirection == .rightToLeft,
                                     reduceMotion: reduceMotion(), motion: motion)
    }

    public func navigationController(_ navigationController: UINavigationController,
                                     interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning)
        -> (any UIViewControllerInteractiveTransitioning)? {
        animationController is FentonStackTransition ? interaction : nil
    }

    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController,
                                     animated: Bool) {
        silenceSystemGestures()
        // The custom transition replaces the system's, so tell VoiceOver the screen changed once the page has landed: focus moves to
        // the page's first element, and the page that left is not reachable (HIG, Accessibility: VoiceOver).
        if animated, isEnabled() { announceScreenChange() }
    }

    // MARK: - Gesture delegate

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, isEnabled(), let navigation else { return false }
        guard navigation.viewControllers.count > 1, navigation.transitionCoordinator == nil else { return false }
        return navigation.topViewController?.navigationItem.hidesBackButton != true
    }

    /// Only an edge pan from outside the stack (a flyout's, on a shell's view that sits above it) runs alongside; one inside the stack
    /// (the columns' pan) never does. The page's scroll views wait for the swipe to fail
    /// (``gestureRecognizer(_:shouldBeRequiredToFailBy:)``) and are cancelled once it begins, so a pop never scrolls the page.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        guard other is UIScreenEdgePanGestureRecognizer, let root = navigation?.view else { return false }
        return !(other.view?.isDescendant(of: root) ?? false)
    }

    /// The pan of any scroll view inside the stack waits for the edge pan to fail. The edge pan fails at once for a touch that does
    /// not start at the edge, so scrolling elsewhere is not delayed.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, let scroll = other.view as? UIScrollView, other === scroll.panGestureRecognizer,
              let root = navigation?.view else { return false }
        return scroll.isDescendant(of: root)
    }

    // MARK: - The swipe

    @objc private func panned(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let sign: CGFloat = recognizer.edges == .right ? -1 : 1
        let progress = min(max(sign * recognizer.translation(in: view).x / max(view.bounds.width, 1), 0), 1)
        switch recognizer.state {
        case .began: beginSwipe()
        case .changed: updateSwipe(progress: progress)
        case .ended: endSwipe(progress: progress, velocity: sign * recognizer.velocity(in: view).x)
        case .cancelled, .failed: endSwipe(progress: 0, velocity: 0, cancelled: true)
        default: break
        }
    }

    /// Whether letting go at `progress` (0 to 1 of the width) with `velocity` (points per second toward the trailing edge) completes
    /// the pop.
    public static func completes(progress: CGFloat, velocity: CGFloat) -> Bool {
        progress > completionFraction || velocity > completionVelocity
    }

    /// Starts the pop the swipe drives; the pages then follow ``updateSwipe(progress:)``. The pop goes through
    /// `popViewController(animated:)`, so a ``FentonNavigationController`` with a ``FentonNavigationController/requestPop`` admits
    /// it first: a deferred approval pops without the swipe.
    public func beginSwipe() {
        guard let navigation, interaction == nil else { return }
        interaction = FentonStackInteraction()
        if navigation.popViewController(animated: true) == nil { interaction = nil }
    }

    /// Moves the pages to `progress` (0 to 1 of the width).
    public func updateSwipe(progress: CGFloat) {
        interaction?.update(min(max(progress, 0), 1))
    }

    /// Lets go of the swipe: completes the pop past halfway or on a flick, otherwise reverses it.
    public func endSwipe(progress: CGFloat, velocity: CGFloat, cancelled: Bool = false) {
        guard let interaction else { return }
        self.interaction = nil
        if !cancelled, Self.completes(progress: progress, velocity: velocity) { interaction.finish() } else { interaction.cancel() }
    }
}
#endif
