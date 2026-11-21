import FentonUIKit
import UIKit

/// The root column: a plain list the shell page links its scroll view to. A row opens its detail with `show(_:sender:)`, the
/// standard UIKit call, so the list neither knows nor cares whether the columns or a navigation stack takes the page.
final class FoundationListViewController: UIViewController, UICollectionViewDelegate {
    private(set) var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, FoundationItem>!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .clear
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        // Rows are measured at the width they are shown at, so a column resize re-measures them.
        let list = FentonWidthAwareCollectionView(frame: view.bounds, collectionViewLayout: layout)
        list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        list.backgroundColor = .clear
        list.delegate = self
        list.accessibilityIdentifier = FoundationIdentifiers.list
        view.addSubview(list)
        collectionView = list

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, FoundationItem> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = item.title
            content.secondaryText = "Opens beside or pushes"
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
            cell.accessibilityIdentifier = FoundationIdentifiers.row(item.number)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: list) { view, indexPath, item in
            view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, FoundationItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(FoundationItem.all)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        open(item)
    }

    /// Shows `item`'s detail through whatever the window gives this list: the columns beside it, or the navigation stack.
    func open(_ item: FoundationItem) {
        guard let environment = (parent?.parent as? FoundationShellPage)?.environment else { return }
        show(FoundationDetailPage(item: item, environment: environment), sender: self)
    }
}
