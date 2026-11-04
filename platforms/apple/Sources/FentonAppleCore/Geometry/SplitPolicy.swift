import Foundation

/// The two-pane arrangements supported by native hosts.
public enum SplitOrientation: Sendable, Equatable {
    case horizontal
    case vertical
}

/// Pure geometry used by native pane hosts and test fixtures.
public struct SplitPolicy: Sendable, Equatable {
    /// Minimum primary pane length.
    public var minimumPrimary: CGFloat
    /// Minimum secondary pane length.
    public var minimumSecondary: CGFloat
    /// Preferred primary pane fraction before minimums are applied.
    public var preferredPrimaryFraction: CGFloat

    /// Creates a clamped, pure pane-sizing policy.
    public init(
        minimumPrimary: CGFloat = 240,
        minimumSecondary: CGFloat = 320,
        preferredPrimaryFraction: CGFloat = 0.34
    ) {
        self.minimumPrimary = max(0, minimumPrimary)
        self.minimumSecondary = max(0, minimumSecondary)
        self.preferredPrimaryFraction = min(max(preferredPrimaryFraction, 0), 1)
    }

    /// Returns the primary length for the available axis length.
    public func primaryLength(for availableLength: CGFloat) -> CGFloat {
        let available = max(0, availableLength)
        guard available > minimumPrimary else { return available }
        let preferred = available * preferredPrimaryFraction
        let lower = minimumPrimary
        let upper = max(lower, available - minimumSecondary)
        return min(max(preferred, lower), upper)
    }
}

/// Pure detent policy. UIKit maps these values to native detents.
public enum SheetHeightPolicy: Sendable, Equatable {
    case medium
    case large
    case mediumAndLarge
}
