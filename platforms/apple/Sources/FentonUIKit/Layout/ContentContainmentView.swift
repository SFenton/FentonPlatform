#if canImport(UIKit)
import UIKit

/// A composition-friendly content container for existing application page bases.
///
/// The application keeps ownership of its page controller, chrome, routes, and
/// tokens. This view owns only the embedded content rectangle, safe-area
/// placement, primary scroll registration, and accessory clearance.
@MainActor
public final class FentonContentContainmentView: UIView {
    /// The safe-area-contained rectangle into which a consumer places content.
    public let contentView = UIView()
    /// Overrides the system safe-area rectangle when the host already owns geometry.
    ///
    /// `nil` uses the helper view's safe area. An explicit value, including
    /// `.zero`, anchors content to the helper's bounds with those insets.
    public var contentInsetsOverride: UIEdgeInsets? {
        didSet { setNeedsLayout() }
    }

    private weak var registeredScrollView: UIScrollView?
    private var registeredScrollBaseline: ScrollBaseline?
    private weak var accessoryView: UIView?
    private var accessoryHeightConstraint: NSLayoutConstraint?
    private var accessoryClearance: CGFloat = 12
    private var contentConstraints: [NSLayoutConstraint] = []
    private var appliedContentInsets: UIEdgeInsets?

    private struct ScrollBaseline {
        let adjustmentBehavior: UIScrollView.ContentInsetAdjustmentBehavior
        let contentInset: UIEdgeInsets
        let indicatorInset: UIEdgeInsets
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        contentConstraints = [
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(contentConstraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Places a consumer-owned view in the safe-area-contained rectangle.
    public func installContentView(_ view: UIView) {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func applyContentConstraints() {
        guard contentConstraints.count == 4 else { return }
        let insets = contentInsetsOverride ?? safeAreaInsets
        guard insets != appliedContentInsets else { return }
        contentConstraints[0].constant = insets.left
        contentConstraints[1].constant = -insets.right
        contentConstraints[2].constant = insets.top
        contentConstraints[3].constant = -insets.bottom
        appliedContentInsets = insets
    }

    /// Registers the primary scroll view for accessory and indicator clearance.
    public func registerMainScrollView(_ scrollView: UIScrollView) {
        if registeredScrollView !== scrollView {
            unregisterMainScrollView()
            registeredScrollView = scrollView
            registeredScrollBaseline = ScrollBaseline(
                adjustmentBehavior: scrollView.contentInsetAdjustmentBehavior,
                contentInset: scrollView.contentInset,
                indicatorInset: scrollView.scrollIndicatorInsets
            )
        }
        applyInsets()
    }

    /// Restores the registered scroll view's original adjustment behavior and insets.
    public func unregisterMainScrollView(_ scrollView: UIScrollView? = nil) {
        guard let registeredScrollView,
              scrollView.map({ registeredScrollView === $0 }) ?? true else { return }
        if let baseline = registeredScrollBaseline {
            registeredScrollView.contentInsetAdjustmentBehavior = baseline.adjustmentBehavior
            registeredScrollView.contentInset = baseline.contentInset
            registeredScrollView.scrollIndicatorInsets = baseline.indicatorInset
        }
        self.registeredScrollView = nil
        registeredScrollBaseline = nil
    }

    private func applyInsets() {
        guard let scrollView = registeredScrollView,
              let baseline = registeredScrollBaseline else { return }
        scrollView.contentInsetAdjustmentBehavior = .never
        let height = accessoryView?.systemLayoutSizeFitting(
            CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height ?? 0
        let clearance = accessoryView == nil ? 0 : height + accessoryClearance
        var contentInset = baseline.contentInset
        contentInset.bottom += clearance
        var indicatorInset = baseline.indicatorInset
        indicatorInset.bottom += clearance
        scrollView.contentInset = contentInset
        scrollView.scrollIndicatorInsets = indicatorInset
    }

    /// Adds an accessory that floats over the bottom edge of the content.
    public func registerAccessoryView(_ accessory: UIView, clearance: CGFloat = 12) {
        accessoryView?.removeFromSuperview()
        accessoryView = accessory
        accessoryClearance = clearance
        accessory.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accessory)
        accessoryHeightConstraint = accessory.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
        NSLayoutConstraint.activate([
            accessory.leadingAnchor.constraint(equalTo: leadingAnchor),
            accessory.trailingAnchor.constraint(equalTo: trailingAnchor),
            accessory.bottomAnchor.constraint(equalTo: bottomAnchor),
            accessoryHeightConstraint!
        ])
        applyInsets()
    }

    /// Removes the accessory and restores the original scroll insets.
    public func clearAccessoryView() {
        accessoryView?.removeFromSuperview()
        accessoryView = nil
        accessoryHeightConstraint = nil
        applyInsets()
    }

    public override func layoutSubviews() {
        applyContentConstraints()
        super.layoutSubviews()
        applyInsets()
    }
}
#endif
