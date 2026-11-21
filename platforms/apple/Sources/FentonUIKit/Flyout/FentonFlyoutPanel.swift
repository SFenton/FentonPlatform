#if os(iOS)
import UIKit

/// The sliding panel: heading and one row per destination, on a regular material that runs under the status bar and the home
/// indicator while the rows stay inside the safe area.
final class FentonFlyoutPanel: UIView {
    // MARK: - Properties

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let closeButton = UIButton(type: .system)
    private let headingRow = UIStackView()
    private let filler = UIView()
    private var rows: [String: FentonFlyoutRow] = [:]
    private var destinations: [FentonFlyoutDestination] = []

    let heading = UILabel()
    var onEscape: () -> Void = {}
    var onClose: () -> Void = {}
    var onSelect: (String) -> Void = { _ in } {
        didSet { rows.values.forEach { $0.onSelect = onSelect } }
    }

    /// The heading's text.
    var title: String {
        get { heading.text ?? "" }
        set { heading.text = newValue }
    }

    /// The close button's and the scrim target's spoken label.
    var closeLabel = "Close Navigation" {
        didSet { closeButton.accessibilityLabel = closeLabel }
    }

    // MARK: - Creating

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Trailing corners round (22 pt, continuous).
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        layer.masksToBounds = true
        blur.frame = bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blur)
        scroll.frame = bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alwaysBounceVertical = false
        scroll.contentInsetAdjustmentBehavior = .always
        scroll.showsVerticalScrollIndicator = false
        addSubview(scroll)

        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            stack.heightAnchor.constraint(greaterThanOrEqualTo: scroll.safeAreaLayoutGuide.heightAnchor)
        ])

        heading.text = "Navigation"
        heading.textColor = .label
        heading.numberOfLines = 0
        heading.accessibilityTraits = .header
        heading.accessibilityIdentifier = "flyout.heading"
        heading.adjustsFontForContentSizeCategory = true
        heading.font = UIFont.preferredFont(forTextStyle: .title2)
        closeButton.accessibilityLabel = closeLabel
        closeButton.accessibilityIdentifier = "flyout.close"
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose() }, for: .touchUpInside)
        headingRow.axis = .horizontal
        headingRow.alignment = .top
        headingRow.spacing = 8
        headingRow.isLayoutMarginsRelativeArrangement = true
        headingRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16)
        headingRow.addArrangedSubview(heading)
        stack.addArrangedSubview(headingRow)
        // The rows keep their size and the room left over sits below them: a stack stretched to the safe area would hand that
        // room to the heading row (rows pushed to the bottom).
        filler.isAccessibilityElement = false
        filler.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        filler.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        stack.addArrangedSubview(filler)
        accessibilityViewIsModal = true
        isAccessibilityElement = false
        accessibilityElements = [heading, closeButton]
        contentSizeChanged()
        // The panel reads its own trait: the flyout's callback can run before the new size has reached this subview.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: FentonFlyoutPanel, _) in view.contentSizeChanged() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Accessibility

    override func accessibilityPerformEscape() -> Bool {
        onEscape()
        return true
    }

    func moveAccessibilityFocusToHeading() {
        UIAccessibility.post(notification: .screenChanged, argument: heading)
    }

    // MARK: - Updating

    func update(destinations: [FentonFlyoutDestination], selection: String?) {
        if self.destinations.map(\.id) != destinations.map(\.id) {
            for row in rows.values { row.removeFromSuperview() }
            rows = rows.filter { id, _ in destinations.contains { $0.id == id } }
            for (index, destination) in destinations.enumerated() {
                let row = rows[destination.id] ?? FentonFlyoutRow(destination: destination)
                rows[destination.id] = row
                row.onSelect = { [weak self] in self?.onSelect($0) }
                stack.insertArrangedSubview(row, at: index + 1)
                stack.setCustomSpacing(stack.spacing, after: row)
            }
            if let last = destinations.last.flatMap({ rows[$0.id] }) { stack.setCustomSpacing(0, after: last) }
            accessibilityElements = [heading, closeButton] + destinations.compactMap { rows[$0.id] }
        }
        self.destinations = destinations
        for destination in destinations {
            rows[destination.id]?.update(destination: destination, isCurrent: destination.id == selection)
        }
    }

    /// At accessibility sizes the panel can take the whole window, with no scrim strip to tap: a close button joins the heading.
    func contentSizeChanged() {
        let large = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        if large, closeButton.superview == nil {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: "xmark.circle.fill")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: .title2))
                .applying(UIImage.SymbolConfiguration(hierarchicalColor: .secondaryLabel))
            configuration.baseForegroundColor = .secondaryLabel
            configuration.contentInsets = .zero
            closeButton.configuration = configuration
            closeButton.setContentHuggingPriority(.required, for: .horizontal)
            closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            headingRow.addArrangedSubview(closeButton)
        } else if !large, closeButton.superview != nil {
            closeButton.removeFromSuperview()
        }
        for row in rows.values { row.contentSizeChanged() }
    }
}
#endif
