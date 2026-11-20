#if os(iOS)
import FentonAppleCore
import UIKit

/// The edge swipe's interactive transition: a plain `UIPercentDrivenInteractiveTransition`. The animator it drives is a paused
/// `UIViewPropertyAnimator`, so the pages follow the finger 1:1 (``FentonStackTransition`` scrubs linearly) and letting go
/// continues or reverses it.
@MainActor
final class FentonStackInteraction: UIPercentDrivenInteractiveTransition {}

/// One push or pop of ``FentonStackMotion``: both pages travel a full width over whatever is behind the stack (the new page in
/// from the trailing edge and the old one out by the leading edge, reversed for a pop and in a right-to-left layout) on the
/// motion's standard spring, with no dim, no shadow and no fade. Under Reduce Motion the slide becomes a cross-fade over
/// ``FentonMotion/quick``. Built on a `UIViewPropertyAnimator` so the interactive pop can scrub it.
@MainActor
final class FentonStackTransition: NSObject, UIViewControllerAnimatedTransitioning {
    /// A push (true) or a pop (false).
    let isPush: Bool
    /// An edge swipe drives this one.
    let isInteractive: Bool
    /// Read once per transition: Reduce Motion changes the next one, not this one.
    let reduceMotion: Bool
    private let motion: FentonMotion
    /// Slides run opposite ways in a right-to-left layout.
    private let direction: CGFloat
    private var animator: UIViewPropertyAnimator?

    init(isPush: Bool, isInteractive: Bool = false, rightToLeft: Bool = false, reduceMotion: Bool, motion: FentonMotion = FentonMotion()) {
        self.isPush = isPush
        self.isInteractive = isInteractive
        self.reduceMotion = reduceMotion
        self.motion = motion
        direction = rightToLeft ? -1 : 1
    }

    /// The duration this transition runs: the standard spring's, or the quick cross-fade's under Reduce Motion.
    var duration: TimeInterval { reduceMotion ? motion.quick : motion.standard.duration }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval { duration }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        makeAnimator(transitionContext).startAnimation()
    }

    func interruptibleAnimator(using transitionContext: any UIViewControllerContextTransitioning) -> any UIViewImplicitlyAnimating {
        makeAnimator(transitionContext)
    }

    private func makeAnimator(_ context: any UIViewControllerContextTransitioning) -> UIViewPropertyAnimator {
        if let animator { return animator }
        let container = context.containerView
        let from = context.view(forKey: .from)
        let to = context.view(forKey: .to)
        let slide = (isPush ? 1 : -1) * direction * container.bounds.width
        if let to {
            to.frame = container.bounds
            if to.superview !== container { container.addSubview(to) }
            // Lay the destination out now, before the first frame: its build is not part of the slide, and a layout the commit does
            // later would land in the animation's first turn.
            to.layoutIfNeeded()
            if reduceMotion { to.alpha = 0 } else { to.transform = CGAffineTransform(translationX: slide, y: 0) }
        }
        let timing: any UITimingCurveProvider = reduceMotion
            ? UICubicTimingParameters(animationCurve: .easeInOut)
            : UISpringTimingParameters(duration: motion.standard.duration, bounce: CGFloat(motion.standard.bounce))
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        animator.scrubsLinearly = true
        let reduce = reduceMotion
        animator.addAnimations {
            if reduce {
                to?.alpha = 1
                from?.alpha = 0
            } else {
                to?.transform = .identity
                from?.transform = CGAffineTransform(translationX: -slide, y: 0)
            }
        }
        animator.addCompletion { _ in
            let finished = !context.transitionWasCancelled
            for view in [from, to] {
                view?.transform = .identity
                view?.alpha = 1
            }
            context.completeTransition(finished)
        }
        self.animator = animator
        return animator
    }
}
#endif
