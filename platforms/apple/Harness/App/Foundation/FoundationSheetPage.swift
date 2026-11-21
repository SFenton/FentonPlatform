import FentonUIKit
import UIKit

/// The sheet the fixture presents through `FentonSheetPresenter`.
final class FoundationSheetPage: UIViewController {
    private let styleLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let title = UILabel()
        title.text = "Sheet"
        title.font = .preferredFont(forTextStyle: .title1)
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits = .header
        title.accessibilityIdentifier = FoundationIdentifiers.sheetTitle
        styleLabel.font = .preferredFont(forTextStyle: .footnote)
        styleLabel.adjustsFontForContentSizeCategory = true
        styleLabel.textColor = .secondaryLabel
        styleLabel.accessibilityIdentifier = FoundationIdentifiers.sheetStyle
        let close = UIButton(configuration: .borderedProminent(), primaryAction: UIAction(title: "Close") { [weak self] _ in
            self?.dismiss(animated: true)
        })
        close.accessibilityIdentifier = FoundationIdentifiers.sheetClose
        let stack = UIStackView(arrangedSubviews: [title, styleLabel, close])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32)
        ])
        refreshStyle()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshStyle()
    }

    /// The style the sheet was presented with, written where a journey can read it.
    private func refreshStyle() {
        let isPageSheet = modalPresentationStyle == .pageSheet && sheetPresentationController != nil
        styleLabel.text = isPageSheet ? "pageSheet" : "other"
    }
}
