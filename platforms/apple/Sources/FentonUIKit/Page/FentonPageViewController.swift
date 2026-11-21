#if os(iOS)
import FentonAppleCore
import FentonAppleTelemetry
import UIKit

/// The base class of a screen: a full-bleed page that the system's bars, large title and scroll edge effect work with, so a feature
/// page puts its content in ``contentView``, names its scroll view, and everything else is the base's.
///
/// **Who owns what.**
/// - The *system* owns the scroll view's insets. The page never writes `contentInset` or the indicator insets: the scroll view
///   keeps `contentInsetAdjustmentBehavior = .automatic`, so the bar, the large title and a pinned accessory arrive as safe-area
///   insets, and ``setPageScrollView(_:)`` hands it to the navigation controller (`setContentScrollView(_:for: .top)`) so the
///   large title tracks it. Content scrolls under the bars.
/// - The *page* owns the geometric side insets: ``contentView`` is full height and full bleed top and bottom, inset only at the
///   sides where the window keeps something out of the way (the folded Duo's vertical bar, a rail). They are measured from where
///   the page's view actually sits in the window, not from the safe area it inherits, so a page in a split pane is not inset by a
///   rail it does not touch.
/// - The *app* owns the chrome. The page draws no menu, profile or quick links: the app subclasses and answers
///   ``barItems()``, calling ``chromeChanged()`` when the answer changes.
///
/// **Title.** ``FentonPageConfiguration/titleStyle`` is the large title by default; a vertical bar (``FentonWindowEnvironment/inVerticalBar``)
/// gets the fixed inline treatment (``FentonFixedBarTitle``). Set ``title`` (or `navigationItem.title`) and nothing else.
///
/// **Edge.** Content fades out under the header: the system's soft top edge effect on iOS 26 and later, a gradient mask before it
/// (``FentonHeaderEdgeFade``).
///
/// **Bottom.** ``bottomAccessory`` is pinned above the bottom safe area on the bar material; its height joins
/// `additionalSafeAreaInsets.bottom` once (``FentonPinnedBar``), so a page never computes a bottom inset for a bar.
///
/// **Layout never writes its own input.** Every layout write is guarded by a change: the content frame, the side safe area, the
/// children's absorbed insets, the fade mask, the follow of the top inset. A second identical layout pass writes nothing, so the
/// page settles in one pass; nothing is written per frame (the scroll observation is reduced to whole points).
@MainActor
open class FentonPageViewController: UIViewController {
    // MARK: - Inputs

    /// The window's facts, observed: the vertical bar, Reduce Transparency, the header's cap.
    public let environment: FentonWindowEnvironment
    /// What the page was asked to do.
    public let configuration: FentonPageConfiguration
    private let telemetry: FentonTelemetry?

    /// Everything the page draws goes here, edge to edge top and bottom and inset at the sides only by the geometric side insets.
    /// It carries the header fade's mask before iOS 26, so content reaches under the bar.
    public let contentView = UIView()
    /// The scroll view that drives the large title, the fade and ``scrollToTop(animated:)``.
    public private(set) var contentScrollView: UIScrollView?
    /// This page is a section's root (the app's shell sets it): a second tap on its tab scrolls it to the top, and ``barItems()`` may
    /// read it to add a menu button.
    public var isSectionRoot = false

    /// A strip pinned above the bottom safe area (a status line), on the bar material. Setting it installs it and adds its height to
    /// the safe area once; setting nil or another view takes it out and gives the inset back.
    public var bottomAccessory: UIView? {
        didSet { if isViewLoaded, oldValue !== bottomAccessory { installBottomAccessory() } }
    }

    /// A hosted test stands in for the Duo's rail with side insets the window does not have; nil (always, outside tests) measures
    /// them from the window.
    public var sideInsetsOverride: UIEdgeInsets? { didSet { if isViewLoaded { layoutContentView() } } }

    override open var title: String? {
        didSet { if isViewLoaded { syncBarTitle() } }
    }

    /// Whether the page is drawn in a sheet (``FentonPageConfiguration/surface``).
    public var isSheet: Bool { configuration.surface == .sheet }

    // MARK: - State

    /// Observations of the environment; they end with the page.
    private let bag = FentonObservationBag()
    private var accessoryBar: FentonPinnedBar?
    private(set) var headerFade: FentonHeaderEdgeFade?
    private let fixedBarTitle: FentonFixedBarTitle
    private var lastTopInset: CGFloat?
    private var didMeasureLayout = false
    private var appliedLeading: [UIBarButtonItem] = []
    private var appliedTrailing: [UIBarButtonItem] = []

    // MARK: - Lifecycle

    /// Creates a page.
    /// - Parameters:
    ///   - environment: The window's facts.
    ///   - configuration: What the page does; the app's own subclass usually fixes it.
    ///   - telemetry: Optional timings and counters (`measure`, `increment` only).
    ///   - title: The page's title.
    public init(environment: FentonWindowEnvironment, configuration: FentonPageConfiguration = .init(),
                telemetry: FentonTelemetry? = nil, title: String? = nil) {
        self.environment = environment
        self.configuration = configuration
        self.telemetry = telemetry
        fixedBarTitle = FentonFixedBarTitle(pointSize: configuration.fixedTitlePointSize,
                                            maximumPointSize: configuration.fixedTitleMaximumPointSize)
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - View

    override open func loadView() {
        view = UIView()
        view.backgroundColor = isSheet ? .systemGroupedBackground : .clear
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        contentView.frame = view.bounds
        contentView.backgroundColor = .clear
        view.addSubview(contentView)

        if configuration.edgeFade {
            let fade = FentonHeaderEdgeFade(masking: contentView, rampHeight: configuration.edgeRampHeight)
            fade.reduceTransparency = environment.reduceTransparency
            fade.increaseContrast = traitCollection.accessibilityContrast == .high
            headerFade = fade
        }
        installBottomAccessory()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: FentonPageViewController, _) in
            page.syncBarTitle()
        }
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (page: FentonPageViewController, _) in
            page.headerFade?.increaseContrast = page.traitCollection.accessibilityContrast == .high
        }
        // Back is the system chevron alone on every page: no previous title beside it (HIG, Toolbars).
        navigationItem.backButtonDisplayMode = .minimal
        // The title mode, the fade's cap and the bar title follow the environment. The tracking closure only reads; the writes run
        // outside it, so a UIKit read made while the bar is laid out can never re-run them.
        bag.observe(track: { [weak self] in
            guard let self else { return }
            _ = environment.inVerticalBar
            _ = environment.headerEdgeCap
            _ = environment.reduceTransparency
        }, apply: { [weak self] in self?.applyChrome() })
        chromeChanged()
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didMeasureLayout {
            didMeasureLayout = true
            telemetry?.measure("page.first-layout") {}
        }
        accessoryBar?.layoutChanged()
        layoutContentView()
    }

    override open func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        layoutContentView()
    }

    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.layoutContentView() }
    }

    override open func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        navigationController?.navigationBar.sizeToFit()
        followTopInset()
        syncBarTitle()
    }

    // MARK: - Bottom accessory

    private func installBottomAccessory() {
        if let old = accessoryBar {
            old.uninstall()
            accessoryBar = nil
        }
        guard let bottomAccessory else { return }
        let bar = FentonPinnedBar.accessory(bottomAccessory)
        accessoryBar = bar
        bar.install(in: self)
        bar.follow(contentScrollView)
    }

    // MARK: - Layout

    /// Full height, but inside the side insets: the folded Duo's vertical bar takes the trailing edge, and a scroll view keeps its
    /// content clear of it. Read again on every layout and whenever the insets change, so a fold, an unfold or a rotation never
    /// leaves the old rail's inset behind. Every write is guarded by a change.
    private func layoutContentView() {
        guard isViewLoaded else { return }
        let side = geometricSideInsets()
        matchSideSafeArea(to: side)
        let frame = view.bounds.inset(by: UIEdgeInsets(top: 0, left: side.left, bottom: 0, right: side.right))
        if contentView.frame != frame { contentView.frame = frame }
        absorbSideInsetsForChildren(side)
        headerFade?.layoutChanged()
        followTopInset()
    }

    /// The side safe areas that actually overlap this page's view: the window's insets (the rail) against where the view sits. A view
    /// inside a navigation controller inside a split pane inherits the whole window inset through the controller hierarchy even when
    /// it ends clear of the rail, so the inherited value is not used for the sides once the page is in a window.
    private func geometricSideInsets() -> UIEdgeInsets {
        if let sideInsetsOverride { return sideInsetsOverride }
        guard let window = view.window else {
            return UIEdgeInsets(top: 0, left: view.safeAreaInsets.left, bottom: 0, right: view.safeAreaInsets.right)
        }
        let frame = view.convert(view.bounds, to: window)
        let safe = window.safeAreaInsets
        return UIEdgeInsets(top: 0, left: max(0, safe.left - frame.minX),
                            bottom: 0, right: max(0, safe.right - (window.bounds.width - frame.maxX)))
    }

    /// Makes this page's own side safe area the geometric one, so the scroll views inside ``contentView`` do not add the inherited
    /// rail inset on top of it (`.automatic` adjustment adds the side safe area). Changes only the page's `additionalSafeAreaInsets`
    /// left and right, and only when the value differs; it settles in one more pass.
    private func matchSideSafeArea(to side: UIEdgeInsets) {
        let inheritedLeft = view.safeAreaInsets.left - additionalSafeAreaInsets.left
        let inheritedRight = view.safeAreaInsets.right - additionalSafeAreaInsets.right
        let left = side.left - inheritedLeft, right = side.right - inheritedRight
        guard abs(additionalSafeAreaInsets.left - left) > 0.5 || abs(additionalSafeAreaInsets.right - right) > 0.5 else { return }
        additionalSafeAreaInsets.left = left
        additionalSafeAreaInsets.right = right
    }

    /// ``contentView`` is already inset by the side insets, but a child view controller inherits this page's side insets through the
    /// controller hierarchy, not by geometry, so a hosted page placed in the content view would be inset a second time. The children
    /// get the side insets taken back. Written only when the value changes.
    private func absorbSideInsetsForChildren(_ insets: UIEdgeInsets) {
        for child in children where child.additionalSafeAreaInsets.left != -insets.left || child.additionalSafeAreaInsets.right != -insets.right {
            child.additionalSafeAreaInsets.left = -insets.left
            child.additionalSafeAreaInsets.right = -insets.right
        }
    }

    /// A scroll view that rests at its top stays at its top when the bar above it changes height (the large title returns after a
    /// rotation, a fold, a tab switch or a sheet): its offset is moved to the new top. Without it the offset keeps the old inset's
    /// value, which is a scroll of the difference, so the bar collapses the title into the header on a page nobody scrolled. A scroll
    /// that is being dragged or is decelerating is never moved.
    public func followTopInset() {
        guard let scroll = contentScrollView, scroll.window != nil else { return }
        let inset = scroll.adjustedContentInset.top
        defer { lastTopInset = inset }
        guard let last = lastTopInset, abs(inset - last) > 0.5, !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating else { return }
        // At the top before the change, by the old inset or by the new one (the system may already have moved it).
        let y = scroll.contentOffset.y
        guard y <= -last + 1.5 || y <= -inset + 1.5 else { return }
        telemetry?.increment("page.follow-top.move")
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -inset), animated: false)
    }

    // MARK: - Scroll view

    /// Adds `scrollView` edge to edge in ``contentView`` and makes it the page's scroll view.
    public func install(scrollView: UIScrollView) {
        loadViewIfNeeded()
        contentView.addSubview(scrollView)
        FentonEmbedding.pin(scrollView, to: contentView)
        setPageScrollView(scrollView)
    }

    /// Names the scroll view that drives the large title, the header fade and scroll-to-top. It is made transparent, scrolls only
    /// when its content outgrows it (``FentonScrollFit``) and keeps `contentInsetAdjustmentBehavior = .automatic`: the system adds
    /// the bar, the large title and the pinned bar's inset, and the page never writes the scroll view's insets.
    public func setPageScrollView(_ scrollView: UIScrollView?) {
        contentScrollView = scrollView
        lastTopInset = nil
        if let scrollView {
            scrollView.backgroundColor = .clear
            scrollView.contentInsetAdjustmentBehavior = .automatic
            FentonScrollFit.apply(to: scrollView)
            setContentScrollView(scrollView, for: .top)
            if configuration.edgeFade {
                FentonHeaderEdgeFade.applySystemEffect(to: scrollView, usesSystemEffect: headerFade?.usesSystemEffect ?? false)
            } else if #available(iOS 26.0, *) {
                scrollView.topEdgeEffect.isHidden = true
            }
        } else {
            setContentScrollView(nil, for: .top)
        }
        headerFade?.follow(scrollView)
        accessoryBar?.follow(scrollView)
    }

    /// Scrolls the page to its top (the second tap on the selected tab). Falls back to the largest visible scroll view when the page
    /// has not named one.
    public func scrollToTop(animated: Bool = true) {
        guard let scroll = contentScrollView ?? FentonScrollLocator.mainScrollView(in: view) else { return }
        let top = -scroll.adjustedContentInset.top
        guard scroll.contentOffset.y > top + 0.5 else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top), animated: animated)
    }

    // MARK: - Chrome

    /// The bar buttons of this page. The default is none: the app's subclass returns its own (menu, profile, actions) and calls
    /// ``chromeChanged()`` whenever the answer would differ.
    open func barItems() -> FentonBarItems { FentonBarItems() }

    /// Writes ``barItems()`` to the navigation item. Call it when the answer changed; a call that finds the very same items already
    /// on the bar writes nothing.
    public func chromeChanged() {
        guard isViewLoaded else { return }
        let items = barItems()
        let item = navigationItem
        if !Self.sameItems(appliedLeading, items.leading) {
            item.leftBarButtonItems = items.leading.isEmpty ? nil : items.leading
            appliedLeading = items.leading
        }
        if !Self.sameItems(appliedTrailing, items.trailing) {
            item.rightBarButtonItems = items.trailing.isEmpty ? nil : items.trailing
            appliedTrailing = items.trailing
        }
    }

    private static func sameItems(_ lhs: [UIBarButtonItem], _ rhs: [UIBarButtonItem]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    /// Reads the environment and the configuration into the bar: the title mode, the fade's cap and Reduce Transparency, the title.
    private func applyChrome() {
        guard isViewLoaded else { return }
        let large = !isSheet && configuration.titleStyle == .large && !environment.inVerticalBar
        let mode: UINavigationItem.LargeTitleDisplayMode = large ? .automatic : .never
        let changed = navigationItem.largeTitleDisplayMode != mode
        if changed { navigationItem.largeTitleDisplayMode = mode }
        headerFade?.cap = isSheet ? nil : environment.headerEdgeCap
        headerFade?.reduceTransparency = environment.reduceTransparency
        syncBarTitle()
        if changed { refreshTitleBar() }
    }

    /// Whether the fixed inline title applies: asked for, or the large title in a vertical bar, which has no room for one. A sheet
    /// keeps the system's inline title.
    private var wantsFixedTitle: Bool {
        guard !isSheet else { return false }
        switch configuration.titleStyle {
        case .fixedInline: return true
        case .large: return environment.inVerticalBar
        case .inline: return false
        }
    }

    private func syncBarTitle() {
        fixedBarTitle.update(item: navigationItem, fallbackTitle: title, fixed: wantsFixedTitle, traits: traitCollection)
    }

    /// A bar that was already showing the page (a rotation swapped the folded Duo's inline-only title for the large one, or back) reads
    /// the title mode again only when it is asked to: without this the page rests with the collapsed title at its top until the first
    /// scroll (`UINavigationBar.sizeToFit()` is the system's own refresh for `largeTitleDisplayMode`).
    private func refreshTitleBar() {
        guard view.window != nil, let bar = navigationController?.navigationBar, navigationController?.topViewController === self else { return }
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
        bar.sizeToFit()
        DispatchQueue.main.async { [weak self] in self?.followTopInset() }
    }
}
#endif
