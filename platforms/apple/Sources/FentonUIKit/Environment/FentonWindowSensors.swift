#if os(iOS)
import UIKit

/// What the window reports about a folding phone, as injectable closures.
///
/// The system answers come from the iOS 27.1 SDK (`UIView.reservedRegions(kind:options:)`, `UITraitCollection.verticalBarEdge`).
/// FentonPlatform requires that SDK or later to build; the calls sit behind a plain `#available(iOS 27.1, *)` runtime check, so an
/// older system reports nothing (no hinge, no vertical bar) exactly as a phone without one does.
///
/// A hosted test replaces the closures to stand in for a Duo in any pose, with no global to set and reset:
///
/// ```swift
/// var sensors = FentonWindowSensors.system
/// sensors.regions = { _, _ in [(frame: CGRect(x: 433, y: 0, width: 1, height: 800), isActive: true)] }
/// let signals = FentonWindowSignals(view: view, environment: environment, sensors: sensors)
/// ```
public struct FentonWindowSensors: Sendable {
    // MARK: - Sensors

    /// The hinge's division regions of `view`, in `view`'s coordinates, each with whether it is active (partly folded).
    /// The `Bool` asks for inactive regions too (a flat device reports its hinge as inactive).
    public var regions: @MainActor @Sendable (UIView, _ includeInactive: Bool) -> [(frame: CGRect, isActive: Bool)]
    /// Whether the system moved the bar items into a vertical bar (a trailing rail), read from the traits.
    public var hasVerticalBar: @MainActor @Sendable (UITraitCollection) -> Bool
    /// System Reduce Motion.
    public var reduceMotion: @MainActor @Sendable () -> Bool
    /// System Reduce Transparency.
    public var reduceTransparency: @MainActor @Sendable () -> Bool

    // MARK: - Creating

    /// Creates sensors; each defaults to the system's answer.
    public init(
        regions: @escaping @MainActor @Sendable (UIView, _ includeInactive: Bool) -> [(frame: CGRect, isActive: Bool)] = FentonWindowSensors.systemRegions,
        hasVerticalBar: @escaping @MainActor @Sendable (UITraitCollection) -> Bool = FentonWindowSensors.systemHasVerticalBar,
        reduceMotion: @escaping @MainActor @Sendable () -> Bool = { UIAccessibility.isReduceMotionEnabled },
        reduceTransparency: @escaping @MainActor @Sendable () -> Bool = { UIAccessibility.isReduceTransparencyEnabled }
    ) {
        self.regions = regions
        self.hasVerticalBar = hasVerticalBar
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
    }

    /// The system's answers.
    public static let system = FentonWindowSensors()

    // MARK: - System answers

    /// `reservedRegions(kind: .division)` on iOS 27.1 and later; nothing before.
    @MainActor
    public static func systemRegions(in view: UIView, includeInactive: Bool) -> [(frame: CGRect, isActive: Bool)] {
        if #available(iOS 27.1, *) {
            return view.reservedRegions(kind: .division, options: includeInactive ? [.includeInactive] : [])
                .map { ($0.frame, $0.isActive) }
        }
        return []
    }

    /// `verticalBarEdge` on iOS 27.1 and later; false before.
    @MainActor
    public static func systemHasVerticalBar(_ traits: UITraitCollection) -> Bool {
        if #available(iOS 27.1, *) { return traits.verticalBarEdge != .unspecified }
        return false
    }
}
#endif
