#if os(iOS)
import FentonAppleCore
import UIKit

/// Keeps a page sheet's form clear of the hinge by using the wider side of it (a sheet can be sized but not offset, so the
/// content takes the inset). A no-op wherever no vertical hinge band crosses the view.
///
/// The band comes from ``FentonWindowEnvironment/band`` (partly folded only). With `leadingOnly` the content takes the leading
/// region of the band instead of its wider side, and touches pass through where the content takes none (a state message: it
/// sits in the leading region, never across the band).
public final class FentonHingeClearingView: UIView {
    // MARK: - Properties

    /// The content kept clear of the band.
    public let content: UIView
    private let environment: FentonWindowEnvironment
    private let leadingOnly: Bool
    private let bag = FentonObservationBag()

    // MARK: - Creating

    /// Creates the view around `content`.
    /// - Parameters:
    ///   - content: The form or message to keep clear.
    ///   - environment: Supplies the hinge band.
    ///   - leadingOnly: Take the band's leading region, not its wider side.
    public init(content: UIView, environment: FentonWindowEnvironment, leadingOnly: Bool = false) {
        self.content = content
        self.environment = environment
        self.leadingOnly = leadingOnly
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = true
        addSubview(content)
        bag.observe(track: { [weak environment] in _ = environment?.band }, apply: { [weak self] in self?.setNeedsLayout() })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        let window = convert(bounds, to: nil)
        let frame = CGRect(x: window.minX.rounded(), y: 0, width: window.width.rounded(), height: 0)
        let band = FentonHingeAvoidance.band(in: frame, hinge: environment.band)
        guard let band else {
            content.frame = bounds
            return
        }
        let region = leadingOnly
            ? (x: CGFloat(0), width: max(band.lowerBound, 0))
            : FentonHingeAvoidance.clearRegion(containerWidth: frame.width, band: band)
        content.frame = CGRect(x: region.x, y: 0, width: region.width, height: bounds.height)
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return leadingOnly && hit === self ? nil : hit
    }
}
#endif
