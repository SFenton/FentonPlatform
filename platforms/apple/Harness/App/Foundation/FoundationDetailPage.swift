import FentonAppleCore
import FentonUIKit
import UIKit

/// A detail page, built on the page base. Beside the list it is a column and shows its own title as content
/// (`FentonColumnTitleHeader`); pushed on the stack it is a full page with the system's large title.
final class FoundationDetailPage: FentonPageViewController {
    private let item: FoundationItem
    private let columnTitle = FentonColumnTitleHeader()
    private let scroll = UIScrollView()

    init(item: FoundationItem, environment: FentonWindowEnvironment) {
        self.item = item
        super.init(environment: environment, title: item.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.accessibilityIdentifier = FoundationIdentifiers.detailScroll
        scroll.alwaysBounceVertical = true
        let heading = UILabel()
        heading.text = item.title
        heading.font = .preferredFont(forTextStyle: .title2)
        heading.adjustsFontForContentSizeCategory = true
        heading.numberOfLines = 0
        heading.accessibilityTraits = .header
        heading.accessibilityIdentifier = FoundationIdentifiers.detailTitle
        let body = UILabel()
        body.text = item.summary
        body.font = .preferredFont(forTextStyle: .body)
        body.adjustsFontForContentSizeCategory = true
        body.numberOfLines = 0
        body.accessibilityIdentifier = FoundationIdentifiers.detailBody
        let stack = UIStackView(arrangedSubviews: [heading, body])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16)
        ])
        install(scrollView: scroll)
        contentView.backgroundColor = .systemBackground
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        // In the columns the section's bar carries the header, so the title is content; on a stack the bar shows it.
        if parent is FentonColumnsViewController {
            columnTitle.attach(to: scroll, in: self, host: contentView, title: item.title)
        } else {
            columnTitle.detach()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        columnTitle.place()
    }
}
