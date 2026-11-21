import CoreGraphics

// MARK: - Split policy

/// When a page may show its on-demand split, and how the panes divide the window.
///
/// | Device / pose | Split |
/// |---|---|
/// | Phone (portrait-locked) | never |
/// | Folding phone folded (outer display) | never |
/// | Folding phone unfolded portrait | never |
/// | Tablet portrait | never |
/// | Folding phone unfolded landscape, tablet landscape | allowed |
///
/// Expressed by geometry, never by device name: a split needs a regular-width window that is wider than tall, with each half at
/// least ``minimumPaneWidth``. Tablet multitasking windows follow the same rule from their own size. Columns follow the Miller
/// model: on the hinge band while partly folded, at the midpoint of the free space with a thin band when flat or on a tablet.
public struct FentonSplitPolicy: Sendable, Equatable {
    // MARK: - Values

    /// Narrowest pane a split may produce.
    public var minimumPaneWidth: CGFloat
    /// Width of the band between panes when no hinge crosses the window: the panes meet at the midpoint with no drawn line.
    public var midpointBandWidth: CGFloat

    /// Creates a policy. The defaults are the shipped values.
    public init(minimumPaneWidth: CGFloat = 360, midpointBandWidth: CGFloat = 1) {
        self.minimumPaneWidth = minimumPaneWidth
        self.midpointBandWidth = midpointBandWidth
    }

    // MARK: - Rules

    /// Whether the window may split.
    /// - Parameters:
    ///   - size: The window (or content area) size in points.
    ///   - isRegularWidth: Horizontal size class is regular.
    public func allowsSplit(size: CGSize, isRegularWidth: Bool) -> Bool {
        guard isRegularWidth, size.width > size.height else { return false }
        return size.width / 2 >= minimumPaneWidth
    }

    /// Where the divider sits: the hinge's x when a vertical fold crosses the window, else the midpoint.
    /// - Parameters:
    ///   - width: Content width.
    ///   - hingeMidX: The vertical fold's centre, if the device reports one inside the window.
    public func dividerX(width: CGFloat, hingeMidX: CGFloat?) -> CGFloat {
        if let hingeMidX, hingeMidX > 0, hingeMidX < width { return hingeMidX }
        return width / 2
    }

    /// Pane widths for a split container, or nil when the container may not split.
    ///
    /// The band is the vertical hinge when one crosses the container (the leading pane ends at its leading edge, the trailing
    /// pane starts at its trailing edge), else ``midpointBandWidth`` centred on the container's midpoint. Each pane must be at
    /// least ``minimumPaneWidth``.
    /// - Parameters:
    ///   - container: The split container's frame in window coordinates.
    ///   - isRegularWidth: Horizontal size class is regular.
    ///   - hinge: The device's division frame in window coordinates, if any.
    public func geometry(container: CGRect, isRegularWidth: Bool, hinge: CGRect?) -> FentonSplitGeometry? {
        guard allowsSplit(size: container.size, isRegularWidth: isRegularWidth) else { return nil }
        var band: ClosedRange<CGFloat>
        var isHinge = false
        if let hinge, hinge.height >= hinge.width, hinge.midX > container.minX, hinge.midX < container.maxX {
            band = hinge.minX...hinge.maxX
            isHinge = true
        } else {
            band = container.midX...container.midX
        }
        if band.upperBound - band.lowerBound < midpointBandWidth {
            let mid = (band.lowerBound + band.upperBound) / 2
            band = (mid - midpointBandWidth / 2)...(mid + midpointBandWidth / 2)
        }
        let leading = band.lowerBound - container.minX
        let trailing = container.maxX - band.upperBound
        guard leading >= minimumPaneWidth, trailing >= minimumPaneWidth else { return nil }
        return FentonSplitGeometry(
            leadingWidth: leading, bandWidth: band.upperBound - band.lowerBound,
            trailingWidth: trailing, isHinge: isHinge
        )
    }

    /// Pane widths for two columns the caller has already decided to show side by side.
    ///
    /// The band is the vertical hinge when one crosses the container and leaves each pane at least ``minimumPaneWidth``;
    /// otherwise the panes share the container equally with `gutter` between them (a tablet, and a folding phone whose hinge
    /// would leave a pane too narrow). Widths are never negative: two-pane screens take their widths from here, not from halving.
    /// - Parameters:
    ///   - container: The columns' container in window coordinates.
    ///   - hinge: The device's division frame in window coordinates, if any.
    ///   - gutter: The gap between panes when no hinge is used.
    public func columnWidths(container: CGRect, hinge: CGRect?, gutter: CGFloat) -> FentonSplitGeometry {
        if let band = FentonHingeAvoidance.band(in: container, hinge: hinge) {
            let leading = band.lowerBound
            let trailing = container.width - band.upperBound
            if leading >= minimumPaneWidth, trailing >= minimumPaneWidth {
                return FentonSplitGeometry(leadingWidth: leading, bandWidth: band.upperBound - band.lowerBound,
                                           trailingWidth: trailing, isHinge: true)
            }
        }
        let gap = max(gutter, 0)
        let each = max((container.width - gap) / 2, 0)
        return FentonSplitGeometry(leadingWidth: each, bandWidth: gap, trailingWidth: each, isHinge: false)
    }
}
