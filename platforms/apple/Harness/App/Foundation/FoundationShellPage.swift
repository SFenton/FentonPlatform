import FentonAppleCore
import FentonUIKit
import UIKit

/// The section page: the one page with a bar, spanning both columns. It hosts the columns in its content view, links the list's
/// scroll view to the bar so the large title collapses and the content scrolls under it, and shows the columns' Back or Close beside
/// its own items.
final class FoundationShellPage: FentonPageViewController, FentonColumnBarHosting {
    let columns: FentonColumnsViewController
    let list: FoundationListViewController
    private let onMenu: () -> Void
    private let onSheet: () -> Void
    private var columnItems: [UIBarButtonItem] = []

    private lazy var menuItem: UIBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal"), primaryAction: UIAction { [weak self] _ in
            self?.onMenu()
        })
        item.accessibilityLabel = "Menu"
        item.accessibilityIdentifier = FoundationIdentifiers.menu
        return item
    }()

    private lazy var sheetItem: UIBarButtonItem = {
        let item = UIBarButtonItem(title: "Sheet", primaryAction: UIAction { [weak self] _ in self?.onSheet() })
        item.accessibilityIdentifier = FoundationIdentifiers.openSheet
        return item
    }()

    init(environment: FentonWindowEnvironment, list: FoundationListViewController, columns: FentonColumnsViewController,
         onMenu: @escaping () -> Void, onSheet: @escaping () -> Void) {
        self.list = list
        self.columns = columns
        self.onMenu = onMenu
        self.onSheet = onSheet
        super.init(environment: environment, title: "Foundation")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        FentonEmbedding.embed(columns, in: self, container: contentView)
        list.loadViewIfNeeded()
        setPageScrollView(list.collectionView)
    }

    // MARK: - Chrome

    override func barItems() -> FentonBarItems {
        FentonBarItems(leading: [menuItem], trailing: [sheetItem] + columnItems)
    }

    func setColumnItems(_ items: [UIBarButtonItem]) {
        columnItems = items
        chromeChanged()
    }
}
