import FentonAppleCore
import FentonUIKit
import UIKit

/// The root of the fixture window: a `FentonRootViewController` whose content is one navigation stack holding the shell page.
///
/// It owns the three decisions the foundation leaves to an app: **when the columns split** (the geometric rule of
/// `FentonSplitPolicy`, asked on every layout), **what the menu lists**, and **what a sheet shows**.
final class FoundationRootViewController: FentonRootViewController {
    private let policy = FentonSplitPolicy()
    private var flyout: FentonFlyoutView?
    private var stackMotion: FentonStackMotion?
    private(set) var shell: FoundationShellPage?
    private(set) var navigation: FentonNavigationController?

    var columns: FentonColumnsViewController? { shell?.columns }

    init() {
        super.init(launchGround: .systemBackground)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The flyout sits over the content and under the launch ground: `setContent(_:below:)` keeps it on top of the stack.
        let flyout = FentonFlyoutView(environment: environment, onDismiss: { [weak self] in self?.flyout?.close(animated: true) },
                                      onSelect: { [weak self] id in self?.select(destination: id) })
        flyout.title = "Foundation"
        flyout.frame = view.bounds
        flyout.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(flyout)
        self.flyout = flyout
    }

    // MARK: - Content

    /// Builds the window's content: the list, the columns around it, the shell page and the stack.
    func makeContent() -> UIViewController {
        loadViewIfNeeded()
        let list = FoundationListViewController()
        let columns = FentonColumnsViewController(root: list, environment: environment) { FoundationEmptyPage() }
        let shell = FoundationShellPage(environment: environment, list: list, columns: columns,
                                        onMenu: { [weak self] in self?.openMenu() },
                                        onSheet: { [weak self] in self?.openSheet() })
        let navigation = FentonNavigationController(rootViewController: shell)
        let motion = FentonStackMotion(navigation: navigation, reduceMotion: { [weak self] in self?.environment.reduceMotion ?? false },
                                       isEnabled: { [weak columns] in !(columns?.isWide ?? false) })
        navigation.delegate = motion
        stackMotion = motion
        self.shell = shell
        self.navigation = navigation
        return navigation
    }

    // MARK: - Layout

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The one rule: split only where both halves keep their minimum width (wide landscape), never by device.
        let regular = traitCollection.horizontalSizeClass == .regular
        columns?.setWide(policy.allowsSplit(size: view.bounds.size, isRegularWidth: regular))
    }

    // MARK: - Menu

    private func openMenu() {
        guard let flyout else { return }
        flyout.setDestinations([
            FentonFlyoutDestination(id: "first", title: "First item", symbol: "arrow.up.to.line",
                                    identifier: FoundationIdentifiers.destination("first")),
            FentonFlyoutDestination(id: "last", title: "Last item", symbol: "arrow.down.to.line",
                                    identifier: FoundationIdentifiers.destination("last"))
        ], selected: nil)
        flyout.open(animated: true)
    }

    private func select(destination id: String) {
        flyout?.close(animated: true)
        guard let item = id == "first" ? FoundationItem.all.first : FoundationItem.all.last else { return }
        shell?.list.open(item)
    }

    // MARK: - Sheet

    private func openSheet() {
        guard let shell else { return }
        FentonSheetPresenter.present(FoundationSheetPage(), from: shell)
    }
}
