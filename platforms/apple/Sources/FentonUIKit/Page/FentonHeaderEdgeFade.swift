#if os(iOS)
import FentonAppleCore
import UIKit

/// Content fades out before it reaches the header, and the header draws no band of its own.
///
/// **iOS 26 and later** draw the edge with the system's soft scroll edge effect on the page's scroll view
/// (``applySystemEffect(to:usesSystemEffect:)``); this object then installs no mask and observes nothing. **Before iOS 26** it is a
/// gradient mask on the page's content view: clear over the header, then a ramp whose top stop follows the scroll offset (opaque at
/// rest, so a page at rest looks untouched; transparent once scrolled a ramp's length). The geometry is ``FentonScrollEdgeFade``;
/// this class only reads the page's scroll view (KVO on `contentOffset`, whole points clamped to the ramp, so only a change that
/// moves the mask reaches it) and its safe area, and writes the mask.
///
/// Nothing is written per frame: a scroll that does not change the whole-point offset inside the ramp, and a layout that does not
/// change the mask's inputs, cost no write (``maskWriteCount`` counts the writes).
@MainActor
public final class FentonHeaderEdgeFade {
    // MARK: - State

    private weak var masked: UIView?
    private weak var scrollView: UIScrollView?
    private let gradient = CAGradientLayer()
    private let rampHeight: CGFloat
    private var offsetObservation: NSKeyValueObservation?
    private var scrollOffset: CGFloat = 0
    private var smallestInset: CGFloat?
    private var lastSize: CGSize = .zero
    private var lastApplied: String?

    /// Whether this fade leaves the edge to the system's effect (no mask, no observation).
    public let usesSystemEffect: Bool
    /// How many times the mask's colours and geometry were written.
    public private(set) var maskWriteCount = 0

    /// Where the inline bar ends (``FentonScrollEdgeFade/edgeCap(statusTop:barHeight:barIsRail:)``); nil for a sheet.
    public var cap: CGFloat? { didSet { if cap != oldValue { apply() } } }
    /// Reduce Transparency turns the ramp into a hard cut (``FentonScrollEdgeFade/ramp(reduceTransparency:increaseContrast:tracksScroll:base:)``).
    public var reduceTransparency = false { didSet { if reduceTransparency != oldValue { apply() } } }
    /// Increase Contrast turns the ramp into a hard cut.
    public var increaseContrast = false { didSet { if increaseContrast != oldValue { apply() } } }

    // MARK: - Era

    /// Whether the running system draws the header edge itself: iOS 26 and later.
    public static var systemDrawsEdge: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// Gives `scroll` the soft top edge effect on iOS 26 and later, or hides the effect when the mask draws the edge instead.
    /// - Parameters:
    ///   - scroll: The page's scroll view.
    ///   - usesSystemEffect: Whether the system effect draws the edge; ``systemDrawsEdge`` by default.
    public static func applySystemEffect(to scroll: UIScrollView, usesSystemEffect: Bool = systemDrawsEdge) {
        guard #available(iOS 26.0, *) else { return }
        if scroll.topEdgeEffect.isHidden != !usesSystemEffect { scroll.topEdgeEffect.isHidden = !usesSystemEffect }
        if usesSystemEffect, scroll.topEdgeEffect.style != .soft { scroll.topEdgeEffect.style = .soft }
    }

    // MARK: - Lifecycle

    /// Creates a fade; the mask is installed on `view`'s layer unless the system draws the edge.
    /// - Parameters:
    ///   - view: The page's content view.
    ///   - rampHeight: The ramp's height in points.
    ///   - usesSystemEffect: Whether the system's effect draws the edge (no mask); ``systemDrawsEdge`` by default. A test passes
    ///     false to run the mask on a newer system.
    public init(masking view: UIView, rampHeight: CGFloat = FentonScrollEdgeFade.rampHeight,
                usesSystemEffect: Bool = FentonHeaderEdgeFade.systemDrawsEdge) {
        masked = view
        self.rampHeight = rampHeight
        self.usesSystemEffect = usesSystemEffect
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        if usesSystemEffect { return }
        view.layer.mask = gradient
    }

    /// Follows `scroll`'s offset; nil stops following (a page with no scroll view keeps the ramp's resting state). With the system
    /// effect nothing is observed.
    public func follow(_ scroll: UIScrollView?) {
        offsetObservation = nil
        scrollView = scroll
        scrollOffset = 0
        guard !usesSystemEffect, let scroll else {
            apply()
            return
        }
        offsetObservation = scroll.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scroll, _ in
            MainActor.assumeIsolated { self?.report(scroll) }
        }
    }

    private func report(_ scroll: UIScrollView) {
        let value = FentonScrollEdgeFade.trackedOffset(contentOffset: scroll.contentOffset.y,
                                                       topInset: scroll.adjustedContentInset.top, rampHeight: rampHeight)
        guard value != scrollOffset else { return }
        scrollOffset = value
        apply()
    }

    // MARK: - Layout

    /// Call from the page's `viewDidLayoutSubviews` and `viewSafeAreaInsetsDidChange`: reads the safe area and rewrites the mask
    /// when its inputs changed.
    public func layoutChanged() {
        guard let view = masked else { return }
        let size = CGSize(width: view.bounds.width.rounded(), height: view.bounds.height.rounded())
        // A new size (rotation, fold, resize) starts over: the bar's height may have changed.
        if size != lastSize {
            lastSize = size
            smallestInset = nil
        }
        let inset = view.safeAreaInsets.top.rounded()
        if inset > 0, inset < (smallestInset ?? .infinity) { smallestInset = inset }
        apply()
    }

    private var tracksScroll: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    private func apply() {
        guard let view = masked, view.layer.mask === gradient, view.bounds.height > 0 else { return }
        let height = view.bounds.height
        let ramp = FentonScrollEdgeFade.ramp(reduceTransparency: reduceTransparency, increaseContrast: increaseContrast,
                                             tracksScroll: tracksScroll, base: rampHeight)
        let header = FentonScrollEdgeFade.clearHeight(
            header: FentonScrollEdgeFade.headerHeight(safeAreaInset: view.safeAreaInsets.top.rounded(), containerOffset: 0),
            smallestInset: smallestInset, cap: cap)
        let progress = FentonScrollEdgeFade.progress(scrollOffset: scrollOffset, rampHeight: ramp)
        let edge = FentonScrollEdgeFade.edgeOpacity(progress: progress)
        let key = "\(height)|\(header)|\(ramp)|\(edge)"
        guard key != lastApplied else { return }
        lastApplied = key
        maskWriteCount += 1
        let start = min(max(header / height, 0), 1)
        let end = min(max((header + ramp) / height, start), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = view.bounds
        gradient.colors = [
            UIColor.clear.cgColor, UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(edge).cgColor, UIColor.black.cgColor, UIColor.black.cgColor,
        ]
        gradient.locations = [0, NSNumber(value: start), NSNumber(value: start), NSNumber(value: end), 1]
        CATransaction.commit()
    }

    // MARK: - Inspection

    /// The mask's gradient stops as last written, for tests: colours' alpha values and locations.
    public var maskStops: (alphas: [CGFloat], locations: [CGFloat])? {
        guard let colors = gradient.colors as? [CGColor], let locations = gradient.locations else { return nil }
        return (colors.map(\.alpha), locations.map { CGFloat(truncating: $0) })
    }
}
#endif
