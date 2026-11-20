#if os(iOS)
import FentonAppleCore
import UIKit

/// Native sheet configuration that leaves application appearance and theme ownership untouched.
public struct FentonSheetConfiguration: Sendable {
    // MARK: - Placement

    /// How a sheet is placed on a folding phone.
    public enum Placement: Sendable, Equatable {
        /// The hinge rules of ``FentonSheetPlacement``: against the leading edge on a device with a hinge, sized to the leading
        /// half beside a vertical hinge, and full height where ``FentonSheetPolicy`` says so. Phones without a hinge and iPads
        /// are unchanged.
        case duoAware
        /// The system's placement and the configured detents, untouched.
        case system
    }

    // MARK: - Properties

    /// The native detent arrangement used by the sheet.
    public var heightPolicy: FentonSheetHeightPolicy
    /// Whether the system grabber is shown for a resizable sheet.
    public var showsGrabber: Bool
    /// An optional native corner radius; nil leaves the system default.
    public var cornerRadius: CGFloat?
    /// How the sheet is placed on a folding phone; ``Placement/duoAware`` by default.
    public var placement: Placement

    // MARK: - Creating

    /// Creates configuration without changing the presenting app's appearance.
    public init(
        heightPolicy: FentonSheetHeightPolicy = .mediumAndLarge,
        showsGrabber: Bool = true,
        cornerRadius: CGFloat? = nil,
        placement: Placement = .duoAware
    ) {
        self.heightPolicy = heightPolicy
        self.showsGrabber = showsGrabber
        self.cornerRadius = cornerRadius
        self.placement = placement
    }
}
#endif
