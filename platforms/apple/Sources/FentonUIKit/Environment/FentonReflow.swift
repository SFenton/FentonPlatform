#if os(iOS)
import FentonAppleCore
import UIKit

/// The one animation of a posture change (partly folded <-> lying flat on a folding phone): layouts that read the fold (grids,
/// panes, splits, centred objects) reflow with ``FentonMotion/standard`` instead of jumping, and with Reduce Motion the old
/// picture cross-fades into the new in ``FentonMotion/crossFade``.
///
/// The fold is written once, in ``FentonWindowSignals/refresh()``. Observers apply it on the next turn of the run loop and mark
/// their views for layout; ``commit(_:before:)`` then lays the whole tree out inside the animation, one turn after those observers
/// have run. Nothing writes a layout input from a layout pass, so the animation cannot feed back.
///
/// ```swift
/// let before = reflow.begin(host, reduceMotion: environment.reduceMotion)   // before the fold is written
/// environment.fold = newFold
/// reflow.commit(host, before: before)
/// ```
@MainActor
public struct FentonReflow {
    private let motion: FentonMotion

    /// Creates a reflow with the app's motion values.
    public init(motion: FentonMotion = FentonMotion()) {
        self.motion = motion
    }

    /// Before the fold is written: with Reduce Motion, a snapshot of `host` laid over it for the cross-fade; otherwise nil.
    /// - Returns: The snapshot view (already added over `host`), which ``commit(_:before:)`` removes.
    public func begin(_ host: UIView, reduceMotion: Bool) -> UIView? {
        guard reduceMotion, let snapshot = host.snapshotView(afterScreenUpdates: false) else { return nil }
        snapshot.frame = host.bounds
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        host.addSubview(snapshot)
        return snapshot
    }

    /// After the fold is written: animates the reflow, and removes the snapshot once it has faded.
    public func commit(_ host: UIView, before snapshot: UIView?) {
        let motion = motion
        // Behind the observation hop (a main-queue task, then a run-loop block) that applies the new fold to the views.
        DispatchQueue.main.async {
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    if let snapshot {
                        host.layoutIfNeeded()
                        UIView.animate(withDuration: motion.crossFade, delay: 0, options: [.curveEaseInOut]) {
                            snapshot.alpha = 0
                        } completion: { _ in snapshot.removeFromSuperview() }
                    } else {
                        FentonAnimations.animate(motion.standard, reduceMotion: false) { host.layoutIfNeeded() }
                    }
                }
            }
        }
    }
}
#endif
