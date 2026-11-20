#if os(iOS)
import FentonAppleCore
import UIKit

/// Keeps a single object that cannot split (an alarm card, a dial, a sign-in form) centred, and moves it to the centre of the
/// leading region only when the hinge band crosses its centred frame
/// (``FentonHingeAvoidance/placement(objectWidth:containerWidth:band:)``).
///
/// The band comes from ``FentonWindowEnvironment/band``, set only while partly folded, so a flat device avoids nothing and a
/// phone without a hinge never changes. Give the object a width with `objectWidth` or an intrinsic content width; without
/// either it is as wide as the container. The content is positioned by frame, in this view's layout pass, from a value that
/// layout never writes, so the placement cannot feed back into itself.
public final class FentonHingeAvoidingView: UIView {
    // MARK: - Properties

    /// The object this view keeps off the hinge.
    public let content: UIView
    private let environment: FentonWindowEnvironment
    private let objectWidth: CGFloat?
    private let bag = FentonObservationBag()

    // MARK: - Creating

    /// Creates the view around `content`.
    /// - Parameters:
    ///   - content: The object to keep clear; it fills the view's height.
    ///   - environment: Supplies the hinge band.
    ///   - objectWidth: The object's natural width; nil reads its intrinsic content width.
    public init(content: UIView, environment: FentonWindowEnvironment, objectWidth: CGFloat? = nil) {
        self.content = content
        self.environment = environment
        self.objectWidth = objectWidth
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = true
        addSubview(content)
        bag.observe(track: { [weak environment] in _ = environment?.band }, apply: { [weak self] in self?.setNeedsLayout() })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Layout

    /// The width the object asks for, at most the container's.
    private var naturalWidth: CGFloat {
        let intrinsic = content.intrinsicContentSize.width
        let asked = objectWidth ?? (intrinsic == UIView.noIntrinsicMetric ? bounds.width : intrinsic)
        return min(asked, bounds.width)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let window = convert(bounds, to: nil)
        let frame = CGRect(x: window.minX.rounded(), y: 0, width: window.width.rounded(), height: 0)
        let band = FentonHingeAvoidance.band(in: frame, hinge: environment.band)
        let placed = FentonHingeAvoidance.placement(objectWidth: naturalWidth, containerWidth: bounds.width, band: band)
        content.frame = CGRect(x: placed.x, y: 0, width: placed.width, height: bounds.height)
    }
}
#endif
