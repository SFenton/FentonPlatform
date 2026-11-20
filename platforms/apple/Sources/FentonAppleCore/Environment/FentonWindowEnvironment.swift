import CoreGraphics
import Observation

/// One observable value for the window: the signals object (in the UIKit module) writes it; pages and columns read it.
///
/// Views bind to it through ``FentonObservation`` so a change to one field re-runs only what read that field.
///
/// **Write access.** The window signals live in `FentonUIKit`, another target, so `internal(set)` cannot reach them and
/// `public` would let any app write the window's facts. The narrowest form that works is `package(set)`: writable by every target
/// of this package, read-only to apps. ``headerEdgeCap`` is the exception, written by the app's shell (which knows the bar), so
/// it is `public`.
@MainActor
@Observable
public final class FentonWindowEnvironment {
    // MARK: - Written by the window signals

    /// The hinge in either pose; ``FentonWindowFold/none`` without one.
    public package(set) var fold: FentonWindowFold = .none
    /// The system vertical bar (a trailing rail) is in use.
    public package(set) var inVerticalBar = false
    /// System Reduce Motion.
    public package(set) var reduceMotion = false
    /// System Reduce Transparency.
    public package(set) var reduceTransparency = false

    // MARK: - Written by the app

    /// Where the inline navigation bar ends (see ``FentonScrollEdgeFade/edgeCap(statusTop:barHeight:barIsRail:)``); nil where
    /// unknown. The app's shell writes it.
    public var headerEdgeCap: CGFloat?

    // MARK: - Derived

    /// The band content keeps clear of: the hinge while partly folded, else nil.
    public var band: CGRect? { fold.band }

    /// Creates an environment with no hinge and every setting off.
    public init() {}
}
