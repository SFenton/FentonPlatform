#if os(iOS)
import FentonAppleCore
import ObjectiveC
import UIKit

/// Where a sheet sits on a folding phone, and when it fills the height.
///
/// **Placement is the system's.** iOS 27 adds `UISheetPresentationController.preferredPlacement` (`.automatic`, `.leading`,
/// `.center`, `.trailing`; "ignored when sourceView is non-nil"). Unfolded in landscape `.automatic` centres a sheet and `.leading`
/// puts it against the left edge; partly folded the system keeps a sheet off the fold whatever is asked; on the folded outer
/// screen and on a phone without a hinge placement changes nothing. So every sheet on a device with a hinge asks for `.leading`
/// (``place(_:in:presence:sensors:)``) and iPad and a phone without a hinge keep `.automatic` (an iPad sheet stays centred).
/// `.trailing` also moves the controls into the vertical bar and is not wanted. Never set a `sourceView` on a sheet (it cancels the
/// placement); a zoom `preferredTransition` source is not one. The hinge reads need the iOS 27.1 SDK, which FentonPlatform
/// requires; they run behind `#available(iOS 27.1, *)` (``FentonWindowSensors``).
///
/// ```swift
/// FentonSheetPresenter.configure(sheet, in: presenter.view)   // detents, grabber, then the one placement call
/// ```
/// **Full height is ours** (``fillsHeight(in:presence:sensors:)``, ``FentonSheetPolicy``): the folded device or a vertical hinge
/// band. A sheet then takes the large detent only. ``PoseWatch`` tells a presenter when the rule changes under an open sheet
/// (fold, unfold, rotation) so it can `animateChanges` its detents and grabber. Nothing here sets a sheet's frame.
@MainActor
public enum FentonSheetPlacement {
    // MARK: - Rules

    /// Whether every sheet fills the height now (``FentonSheetPolicy/fillsHeight(hasHinge:hinge:)``): the folded device, or
    /// landscape beside the vertical hinge.
    /// - Parameters:
    ///   - view: Any view in the window (the sheet's container, or the presenter's); nil reads the device record only.
    ///   - presence: The record that this device has a hinge.
    ///   - sensors: Where the hinge is read from.
    public static func fillsHeight(in view: UIView?, presence: FentonHingePresence = .shared, sensors: FentonWindowSensors = .system) -> Bool {
        let hinge = view.flatMap { FentonWindowSignals.fold(in: $0, sensors: sensors).hinge }
        return FentonSheetPolicy.fillsHeight(hasHinge: hasHinge(in: view, hinge: hinge, presence: presence, sensors: sensors), hinge: hinge)
    }

    /// Whether the device has a hinge: one has been reported (``FentonHingePresence``), or `view` sees one.
    public static func hasHinge(in view: UIView?, presence: FentonHingePresence = .shared, sensors: FentonWindowSensors = .system) -> Bool {
        hasHinge(in: view, hinge: view.flatMap { FentonWindowSignals.fold(in: $0, sensors: sensors).hinge }, presence: presence, sensors: sensors)
    }

    private static func hasHinge(in view: UIView?, hinge: CGRect?, presence: FentonHingePresence, sensors: FentonWindowSensors) -> Bool {
        if presence.hasHinge || hinge != nil { return true }
        // The folded outer screen reports no hinge region, and a cold launch has not always seen a hinge change yet; but its
        // system vertical bar (`verticalBarEdge`) is set on any view of the window, so a sheet asked for before the shell has
        // said so still knows.
        if let view, sensors.hasVerticalBar(view.traitCollection) {
            presence.record(hinge: nil, hasVerticalBar: true)
            return true
        }
        return false
    }

    /// The size a sheet takes in the leading half beside a vertical hinge (``FentonSheetPolicy/leadingHalfWidth(fold:freeWidth:)``),
    /// full height less the system's margin; nil elsewhere. Partly folded it ends at the hinge; lying flat at the midpoint of the
    /// free space (the window less the trailing rail), where the page divides.
    public static func leadingHalfSize(in view: UIView?, sensors: FentonWindowSensors = .system) -> CGSize? {
        guard let view, let window = view.window ?? (view as? UIWindow) else { return nil }
        let fold = FentonWindowSignals.fold(in: window, sensors: sensors)
        guard let width = FentonSheetPolicy.leadingHalfWidth(
            fold: fold, freeWidth: FentonWindowSignals.freeWidth(in: window, sensors: sensors)
        ) else { return nil }
        return CGSize(width: width, height: (window.bounds.height - 2 * FentonSheetPolicy.halfMargin).rounded(.down))
    }

    // MARK: - Placing

    /// Places `sheet`: against the leading edge on a device with a hinge (`preferredPlacement`, iOS 27; every other device and
    /// system keeps `.automatic`), and beside a vertical hinge sized to the leading half through the system's own sizing
    /// (`prefersPageSizing = false` plus `preferredContentSize`), so the system lays the sheet out at that size and nothing
    /// resizes it in a layout pass. Every sheet path calls it after configuring the sheet, and again (outside layout) when
    /// ``PoseWatch`` reports a change.
    public static func place(
        _ sheet: UISheetPresentationController?,
        in view: UIView?,
        presence: FentonHingePresence = .shared,
        sensors: FentonWindowSensors = .system
    ) {
        guard let sheet else { return }
        if #available(iOS 27.0, *) {
            sheet.preferredPlacement = hasHinge(in: view, presence: presence, sensors: sensors) ? .leading : .automatic
        }
        // The sheet holds its controller weakly: one already released has nothing to place.
        let optionalPresented: UIViewController? = sheet.presentedViewController
        guard let presented = optionalPresented else { return }
        if let size = leadingHalfSize(in: view, sensors: sensors) {
            // The sheet's own size, kept for when it leaves the half (a rotation to portrait, a fold).
            if objc_getAssociatedObject(presented, &ownSizeKey) == nil {
                objc_setAssociatedObject(presented, &ownSizeKey, NSValue(cgSize: presented.preferredContentSize), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            sheet.prefersPageSizing = false
            if presented.preferredContentSize != size { setContentSize(size, on: presented) }
        } else {
            sheet.prefersPageSizing = presented.modalPresentationStyle == .pageSheet
            if let own = objc_getAssociatedObject(presented, &ownSizeKey) as? NSValue {
                objc_setAssociatedObject(presented, &ownSizeKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                setContentSize(own.cgSizeValue, on: presented)
            }
        }
    }

    /// Sets `size` so that the controller reports it back. A navigation controller adds its visible bar's height to the
    /// `preferredContentSize` it is given (measured: 684 reads back 738 with a 54 pt bar), which would make a sheet taller than the
    /// half it should fill; the bar is taken off first. On a device whose bar is vertical it adds the bar's width instead, once the
    /// sheet is up (measured: 580 read back 668 with the 88 pt vertical bar, so a sheet resized while presented came out 88 pt
    /// wider), so whatever it still adds on either axis is read back and taken off once.
    public static func setContentSize(_ size: CGSize, on presented: UIViewController) {
        var adjusted = size
        if let navigation = presented as? UINavigationController, !navigation.isNavigationBarHidden {
            adjusted.height = max(0, size.height - navigation.navigationBar.frame.height)
        }
        presented.preferredContentSize = adjusted
        let reported = presented.preferredContentSize
        guard reported != size else { return }
        presented.preferredContentSize = CGSize(
            width: max(0, adjusted.width - (reported.width - size.width)),
            height: max(0, adjusted.height - (reported.height - size.height))
        )
    }

    nonisolated(unsafe) private static var ownSizeKey: UInt8 = 0

    // MARK: - Watching

    /// Notices the pose changing under an open sheet: the full-height rule, or the leading-half size (folded to unfolded
    /// landscape keeps the rule but gains the half). A presenter calls ``changed(in:)`` from its layout pass and, when it answers
    /// true, re-applies its detents, grabber and ``place(_:in:presence:sensors:)`` inside `animateChanges`, on the next turn of the
    /// run loop.
    public struct PoseWatch {
        private struct Pose: Equatable {
            var fills: Bool
            var half: CGSize?
        }

        private var applied: Pose?
        private let presence: FentonHingePresence
        private let sensors: FentonWindowSensors

        /// Creates a watch that reads the pose through `presence` and `sensors`.
        @MainActor
        public init(presence: FentonHingePresence = .shared, sensors: FentonWindowSensors = .system) {
            self.presence = presence
            self.sensors = sensors
        }

        @MainActor
        private func pose(in view: UIView?) -> Pose {
            Pose(
                fills: FentonSheetPlacement.fillsHeight(in: view, presence: presence, sensors: sensors),
                half: FentonSheetPlacement.leadingHalfSize(in: view, sensors: sensors)
            )
        }

        /// Records the pose now (as the sheet is configured) so the first layout pass is not read as a change.
        @MainActor
        public mutating func record(in view: UIView?) { applied = pose(in: view) }

        /// Whether the pose differs from the one recorded; records the new one.
        @MainActor
        public mutating func changed(in view: UIView?) -> Bool {
            let pose = pose(in: view)
            defer { applied = pose }
            guard let applied else { return false }
            return applied != pose
        }
    }
}
#endif
