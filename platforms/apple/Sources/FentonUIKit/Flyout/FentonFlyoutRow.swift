#if os(iOS)
import UIKit

/// One destination in the panel: the symbol, the name and, when set, a badge. The current destination sits on a tint of the
/// view's tint colour.
final class FentonFlyoutRow: UIControl {
    // MARK: - Properties

    private(set) var destination: FentonFlyoutDestination
    private let icon = UIImageView()
    private let title = UILabel()
    private let badge = FentonFlyoutBadgeLabel()
    private let highlight = UIView()
    private let content = UIStackView()
    private var iconWidth: NSLayoutConstraint?
    private var isCurrent = false

    /// A tap on the row chooses its destination.
    var onSelect: (String) -> Void = { _ in }

    // MARK: - Creating

    init(destination: FentonFlyoutDestination) {
        self.destination = destination
        super.init(frame: .zero)
        highlight.backgroundColor = tintColor.withAlphaComponent(0.18)
        highlight.layer.cornerRadius = 12
        highlight.layer.cornerCurve = .continuous
        highlight.isUserInteractionEnabled = false
        highlight.isHidden = true
        addSubview(highlight)

        icon.contentMode = .center
        icon.tintColor = .label
        icon.isAccessibilityElement = false
        title.textColor = .label
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        badge.textColor = .white
        badge.font = UIFont.preferredFont(forTextStyle: .caption1).withWeight(.bold)
        badge.adjustsFontForContentSizeCategory = true
        badge.backgroundColor = .systemRed
        badge.layer.masksToBounds = true
        badge.textAlignment = .center
        badge.insets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        badge.isAccessibilityElement = false
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = 16
        content.isUserInteractionEnabled = false
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        content.translatesAutoresizingMaskIntoConstraints = false
        [icon, title, spacer, badge].forEach { content.addArrangedSubview($0) }
        addSubview(content)
        let width = icon.widthAnchor.constraint(equalToConstant: UIFontMetrics(forTextStyle: .body).scaledValue(for: 28))
        iconWidth = width
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            width
        ])
        isAccessibilityElement = true
        addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onSelect(self.destination.id)
        }, for: .touchUpInside)
        update(destination: destination, isCurrent: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Updating

    func update(destination: FentonFlyoutDestination, isCurrent: Bool) {
        self.destination = destination
        self.isCurrent = isCurrent
        highlight.isHidden = !isCurrent
        badge.isHidden = destination.badge == nil
        badge.text = destination.badge
        title.text = destination.title
        accessibilityIdentifier = destination.identifier
        let body = UIFont.preferredFont(forTextStyle: .body)
        title.font = isCurrent ? body.withWeight(.semibold) : body
        let symbolFont = UIFont.preferredFont(forTextStyle: .body).withWeight(.semibold)
        icon.image = UIImage(systemName: destination.symbol, withConfiguration: UIImage.SymbolConfiguration(font: symbolFont))
        accessibilityLabel = destination.spokenLabel ?? destination.title
        accessibilityTraits = isCurrent ? [.button, .selected] : .button
        setNeedsLayout()
    }

    func contentSizeChanged() {
        iconWidth?.constant = UIFontMetrics(forTextStyle: .body).scaledValue(for: 28, compatibleWith: traitCollection)
        update(destination: destination, isCurrent: isCurrent)
    }

    // MARK: - UIView

    override func tintColorDidChange() {
        super.tintColorDidChange()
        highlight.backgroundColor = tintColor.withAlphaComponent(0.18)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds
        badge.layer.cornerRadius = badge.bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 48) }
}

/// A label with insets, for the row's badge.
final class FentonFlyoutBadgeLabel: UILabel {
    var insets = UIEdgeInsets.zero { didSet { invalidateIntrinsicContentSize() } }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fitted = super.sizeThatFits(CGSize(width: max(size.width - insets.left - insets.right, 0), height: max(size.height - insets.top - insets.bottom, 0)))
        return CGSize(width: fitted.width + insets.left + insets.right, height: fitted.height + insets.top + insets.bottom)
    }
}

extension UIFont {
    /// The same font in `weight`, keeping its size and Dynamic Type scaling base.
    fileprivate func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
#endif
