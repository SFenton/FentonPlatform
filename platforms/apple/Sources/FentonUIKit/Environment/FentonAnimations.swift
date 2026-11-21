#if os(iOS)
import FentonAppleCore
import UIKit

/// ``FentonMotion`` values as UIKit animations. Reduce Motion is passed in (the caller reads
/// ``FentonWindowEnvironment/reduceMotion``), never read from a global, so a test decides it.
@MainActor
public enum FentonAnimations {
    /// Runs `changes` with `spring`, or applies them at once under Reduce Motion.
    ///
    /// Never let a slide, scale or layout move run under Reduce Motion; a change that may fade (an opacity or colour change)
    /// calls `UIView.animate` with ``FentonMotion/crossFade`` itself.
    /// - Parameters:
    ///   - spring: The spring's duration and bounce.
    ///   - reduceMotion: System Reduce Motion is on: apply the changes without animating.
    ///   - changes: The animated changes.
    public static func animate(_ spring: FentonMotion.Spring, reduceMotion: Bool, _ changes: @escaping () -> Void) {
        guard !reduceMotion else {
            changes()
            return
        }
        UIView.animate(
            springDuration: spring.duration,
            bounce: CGFloat(spring.bounce),
            initialSpringVelocity: 0,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes
        )
    }
}
#endif
