#if os(iOS)
import FentonAppleCore
import UIKit

/// Gives a screen that is not a ``FentonPageViewController`` the page chrome anyway, with the screen's view filling
/// ``FentonPageViewController/contentView``.
///
/// **On the page surface** a plain controller wrapped in a host looks like every other page: the large title, the fade, the side
/// insets. The largest scroll view the screen shows becomes the page's scroll view once it is on screen (``FentonScrollLocator``).
///
/// **On the sheet surface** (``FentonPageConfiguration/surface`` `.sheet`, with `linksScroll` false) the hosted controller keeps
/// everything else it had:
/// - its title and `navigationItem` bar items, back button and title view are mirrored onto the host's, which is what the sheet's
///   navigation bar reads;
/// - its scroll view is not taken over (no fade, no scroll-fit rule): it scrolls and bounces as it did.
///
/// The host forwards the status-bar style and visibility of the hosted controller.
///
/// **Subclassing.** An app subclasses the host to give every hosted screen its own bar: override ``barItems()`` (inherited from
/// ``FentonPageViewController``) to answer the app's buttons, ``syncChrome()`` to change how the screen's `navigationItem` is
/// mirrored on a sheet, and forward any app protocol (a sheet-fitting protocol, say) by reading ``child``. Pass a `make` closure to
/// ``wrapped(_:environment:make:)`` so the app's subclass is what wraps a plain controller.
@MainActor
open class FentonPageHost: FentonPageViewController {
    // MARK: - State

    /// The hosted screen.
    public let child: UIViewController
    private let linksScroll: Bool
    private var linked = false
    private var observations: [NSKeyValueObservation] = []

    // MARK: - Lifecycle

    /// Creates a host around `child`.
    /// - Parameters:
    ///   - child: The screen to host.
    ///   - environment: The window's facts.
    ///   - linksScroll: Whether the screen's main scroll view becomes the page's (the large title, the fade, scroll-to-top). True on
    ///     the page surface; a sheet leaves the screen's scroll view alone.
    ///   - configuration: What the page does.
    public init(child: UIViewController, environment: FentonWindowEnvironment, linksScroll: Bool = true,
                configuration: FentonPageConfiguration = .init()) {
        self.child = child
        self.linksScroll = linksScroll
        super.init(environment: environment, configuration: configuration, title: child.title)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `controller` as a page: itself when it already is one (or is a navigation controller, which brings its own bar), else hosted.
    /// - Parameters:
    ///   - controller: The screen to show as a page.
    ///   - environment: The window's facts.
    ///   - make: Builds the host for a plain controller; an app passes its subclass here. Defaults to ``FentonPageHost``.
    public static func wrapped(
        _ controller: UIViewController,
        environment: FentonWindowEnvironment,
        make: (UIViewController, FentonWindowEnvironment) -> FentonPageHost = { FentonPageHost(child: $0, environment: $1) }
    ) -> UIViewController {
        if controller is FentonPageViewController || controller is UINavigationController { return controller }
        return make(controller, environment)
    }

    // MARK: - View

    override open func viewDidLoad() {
        super.viewDidLoad()
        child.view.backgroundColor = child.view.backgroundColor ?? .clear
        FentonEmbedding.embed(child, in: self, container: contentView)
        title = child.title
        if isSheet { mirrorChrome() }
    }

    override open func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        if isSheet { syncChrome() }
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard linksScroll, !linked, let scroll = FentonScrollLocator.mainScrollView(in: child.view) else { return }
        linked = true
        setPageScrollView(scroll)
    }

    override open var childForStatusBarStyle: UIViewController? { child }
    override open var childForStatusBarHidden: UIViewController? { child }

    // MARK: - Chrome mirrored from the hosted screen

    /// The hosted screen configures its own `navigationItem` (it was the navigation controller's page before); a sheet's bar reads
    /// the host's. Values the screen has set are copied across now and whenever they change; the host's own stay where the screen
    /// sets nothing.
    private func mirrorChrome() {
        let item = child.navigationItem
        observations = [
            item.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
            item.observe(\.rightBarButtonItems) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
            item.observe(\.leftBarButtonItems) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
            item.observe(\.hidesBackButton) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
            item.observe(\.titleView) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
            child.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
        ]
        syncChrome()
    }

    /// Copies the hosted screen's title, bar items, back button and title view onto the host's navigation item; called on a sheet
    /// when the screen sets any of them. A subclass overrides it to add or filter items, calling `super` for the rest.
    open func syncChrome() {
        let source = child.navigationItem
        let host = navigationItem
        if let title = source.title ?? child.title, host.title != title { host.title = title }
        if let right = source.rightBarButtonItems, !right.isEmpty, host.rightBarButtonItems != right { host.rightBarButtonItems = right }
        if let left = source.leftBarButtonItems, !left.isEmpty, host.leftBarButtonItems != left { host.leftBarButtonItems = left }
        if host.hidesBackButton != source.hidesBackButton { host.hidesBackButton = source.hidesBackButton }
        if host.leftItemsSupplementBackButton != source.leftItemsSupplementBackButton {
            host.leftItemsSupplementBackButton = source.leftItemsSupplementBackButton
        }
        if let titleView = source.titleView, host.titleView !== titleView { host.titleView = titleView }
    }
}
#endif
