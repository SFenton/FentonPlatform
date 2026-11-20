import CoreGraphics

/// Resolved pane widths for an open split.
public struct FentonSplitGeometry: Sendable, Equatable {
    /// Leading (list) pane width.
    public var leadingWidth: CGFloat
    /// Gap between the panes: the hinge, or the midpoint band.
    public var bandWidth: CGFloat
    /// Trailing (detail) pane width.
    public var trailingWidth: CGFloat
    /// The band is the device hinge.
    public var isHinge: Bool

    /// Creates a geometry from its four values.
    public init(leadingWidth: CGFloat, bandWidth: CGFloat, trailingWidth: CGFloat, isHinge: Bool) {
        self.leadingWidth = leadingWidth
        self.bandWidth = bandWidth
        self.trailingWidth = trailingWidth
        self.isHinge = isHinge
    }
}
