#if os(iOS)
import FentonAppleCore
import UIKit

/// Column navigation: the one way a page opens another page beside it.
///
/// **Miller columns, two visible at a time.** The columns are `[root] + entries`. The window shows the last two: with no entries,
/// the root and the app's empty state (``init(root:environment:splitPolicy:gutter:appearance:motion:makePlaceholder:)``'s
/// `makePlaceholder`); with one, the root and that page; with more, the page that was on the right slides over to the left column
/// and the new page comes in on the right. Back and Close reverse it. A page never moves between parents: every entry has one
/// host that is slid by frame, so nothing reloads or blinks.
///
/// **Navigation.** A page opens another with `show(_:sender:)` (the standard UIKit call; this controller is its target for any
/// page it hosts) or ``open(_:tag:atDepth:animated:pushesWhenNarrow:onUserClose:)`` from the root. The rule is one: the stack is cut
/// back to the sender's own column, then the page is appended. A tap in the right column appends (drills); a tap in the left
/// column replaces what is on the right. Back (``popTop(animated:)``) and Close (``closeAll(animated:)``) are bar items and a
/// screen-edge pan.
///
/// **Narrow windows.** Where the window does not split (``FentonSplitPolicy/allowsSplit(size:isRegularWidth:)``: iPhone, portrait,
/// the folded Duo) ``isWide`` is false: the root fills the container, no entry is kept, and a page that is shown goes onto the
/// enclosing navigation stack as a push. The owner flips ``setWide(_:)`` (the section's controller for route-backed sections; the
/// page for its own detail pane). Pages that were open when the window stopped splitting are handed to the navigation stack, so a
/// fold or rotation loses nothing, and they come back as columns when the window splits again (``adopt(_:)`` does the same by hand).
///
/// **No route storage.** The columns hold pages, not routes. An owner that keeps its own route state tags each page and calls
/// ``reconcile(tags:make:animated:)`` when the state changes; ``onUserPop`` reports how deep the tagged pages now go when the
/// person leaves one. FentonPlatform never stores or interprets a route.
///
/// **Geometry.** The columns divide as every two-pane screen does (``FentonSplitPolicy/columnWidths(container:hinge:gutter:)``):
/// on the hinge band while the Duo is partly folded, at the free space's midpoint with a 1 pt band when it lies flat or on an iPad.
/// A posture change reflows through the window's layout pass (``FentonReflow`` animates it); this controller writes no layout input
/// from layout.
///
/// **Bars.** The container draws no header and hosts no navigation controllers. The section's own bar spans the window above both
/// columns, as on every top-level page. Back (a drilled page) or Close (the first page), with any bar items the open page has of
/// its own, go to the nearest ancestor that is a ``FentonColumnBarHosting``. A page's title is content at the top of its scroll view
/// (``FentonColumnTitleHeader``).
///
/// **Guards.** A page may hold itself open (``FentonColumnPopGuarding``, ``FentonColumnExitRequesting``): a ``FentonColumnPopDecision/block``
/// stops Back, Close and the edge pan; ``FentonColumnPopDecision/confirmDiscard`` asks first.
@MainActor
open class FentonColumnsViewController: UIViewController {
    // MARK: - Inputs

    private let rootController: UIViewController?
    private let suppliedRootView: UIView?
    /// The root column's view. A root controller's view is read here, when the columns' own view loads, never during `init`.
    private var rootView: UIView {
        if let suppliedRootView { return suppliedRootView }
        // `rootController` is non-nil whenever no view was supplied.
        return rootController?.view ?? UIView()
    }
    private let environment: FentonWindowEnvironment
    private let splitPolicy: FentonSplitPolicy
    private let gutter: CGFloat
    private let appearance: FentonColumnsAppearance
    private let motion: FentonMotion
    private let makePlaceholder: () -> UIViewController

    // MARK: - State

    private let bag = FentonObservationBag()
    private var placeholder: UIViewController?
    private let band = UIView()
    private var hinge: CGRect?
    private var handedOff: [UIViewController] = []
    private var animations = 0
    /// Bumped by every commit; a deferred step (the placeholder's fade-out before the first page comes in) runs only if it still matches.
    private var generation = 0
    /// True while the empty state fades out ahead of the first page, which has not been installed yet.
    private var openingPending = false
    private var edgePan: UIScreenEdgePanGestureRecognizer?
    private var pageItemsObservation: [NSKeyValueObservation] = []
    private var backAnimator: UIViewPropertyAnimator?
    private let exitItem = UIBarButtonItem()
    private var exitAction: (() -> Void)?

    // MARK: - Public state

    /// The pages open beside the root, oldest first.
    public private(set) var entries: [FentonColumnEntry] = []
    /// Whether the window shows columns side by side. False: the root fills the container and pages are pushed.
    public private(set) var isWide = false
    /// Whether the columns' own edge pan can act: wide with a page open to close. A navigation stack's swipe back stands down
    /// meanwhile (``FentonStackMotion`` does not begin while ``isWide`` is true when its `isEnabled` says so), so one swipe closes
    /// the column or pops the page, never both.
    public var takesEdgePan: Bool { isWide && !entries.isEmpty }
    /// The accessibility identifier of the trailing (open) column's host; an app that tests its detail pane by another name sets it.
    public var trailingIdentifier = "split.trailing"
    /// Whether pages that are open when the window stops splitting are pushed on the enclosing navigation stack. A detail pane the
    /// owner presents some other way (a sheet) turns it off.
    public var pushesCollapsedPages = true
    /// Called after the person pops pages (Back, Close, the edge pan), with how many leading entries carry a tag: the owner trims
    /// the state it keeps (its route path) to that depth.
    public var onUserPop: ((_ taggedDepth: Int) -> Void)?
    /// Called when ``isWide`` changes.
    public var onWideChange: ((Bool) -> Void)?
    /// Called when a transition has settled.
    public var onSettled: (() -> Void)?
    /// Whether a transition is running or about to; coordinators wait for it before they publish or navigate.
    public var isTransitioning: Bool { openingPending || animations > 0 || backAnimator != nil }

    // MARK: - Creating

    /// - Parameters:
    ///   - root: The root column; it becomes a child of this controller.
    ///   - environment: The window's facts: the hinge band and Reduce Motion.
    ///   - splitPolicy: The rule that sizes the two columns (the minimum pane width).
    ///   - gutter: The band between the columns when there is no hinge to sit on.
    ///   - appearance: The ground, the hairline and the words.
    ///   - motion: The slide's spring and the cross-fade's duration.
    ///   - makePlaceholder: The empty state shown in the right column while nothing is open.
    public init(root: UIViewController, environment: FentonWindowEnvironment, splitPolicy: FentonSplitPolicy = FentonSplitPolicy(),
                gutter: CGFloat = 1, appearance: FentonColumnsAppearance = FentonColumnsAppearance(), motion: FentonMotion = FentonMotion(),
                makePlaceholder: @escaping () -> UIViewController) {
        rootController = root
        suppliedRootView = nil
        self.environment = environment
        self.splitPolicy = splitPolicy
        self.gutter = gutter
        self.appearance = appearance
        self.motion = motion
        self.makePlaceholder = makePlaceholder
        super.init(nibName: nil, bundle: nil)
    }

    /// Creates columns whose root column is a plain view (a page's scroll view or host), which this controller adds to its own view
    /// and moves by frame like a controller's view; no controller becomes its child.
    /// - Parameters:
    ///   - rootView: The root column's view.
    ///   - environment: The window's facts: the hinge band and Reduce Motion.
    ///   - splitPolicy: The rule that sizes the two columns (the minimum pane width).
    ///   - gutter: The band between the columns when there is no hinge to sit on.
    ///   - appearance: The ground, the hairline and the words.
    ///   - motion: The slide's spring and the cross-fade's duration.
    ///   - makePlaceholder: The empty state shown in the right column while nothing is open.
    public init(rootView: UIView, environment: FentonWindowEnvironment, splitPolicy: FentonSplitPolicy = FentonSplitPolicy(),
                gutter: CGFloat = 1, appearance: FentonColumnsAppearance = FentonColumnsAppearance(), motion: FentonMotion = FentonMotion(),
                makePlaceholder: @escaping () -> UIViewController) {
        rootController = nil
        suppliedRootView = rootView
        self.environment = environment
        self.splitPolicy = splitPolicy
        self.gutter = gutter
        self.appearance = appearance
        self.motion = motion
        self.makePlaceholder = makePlaceholder
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - View

    open override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        if let rootController { addChild(rootController) }
        rootView.frame = view.bounds
        view.addSubview(rootView)
        rootController?.didMove(toParent: self)
        band.isUserInteractionEnabled = false
        band.isAccessibilityElement = false
        band.accessibilityElementsHidden = true
        band.isHidden = true
        view.addSubview(band)
        // The tracking closure only reads the fold; the write and the layout request run outside it.
        bag.observe(track: { [weak self] in _ = self?.environment.fold }, apply: { [weak self] in
            guard let self else { return }
            self.hinge = self.environment.band
            self.view.setNeedsLayout()
        })
        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePanned(_:)))
        pan.edges = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        pan.isEnabled = false
        view.addGestureRecognizer(pan)
        edgePan = pan
        exitItem.primaryAction = UIAction { [weak self] _ in self?.exitAction?() }
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard animations == 0 else { return }
        applyResting()
    }

    // MARK: - Geometry

    private struct Rects {
        var leading: CGRect
        var trailing: CGRect
        var band: CGRect
        var isHinge = false
    }

    private var rects: Rects {
        let bounds = view.bounds
        guard isWide, bounds.width > 0 else {
            return Rects(leading: bounds, trailing: CGRect(x: bounds.width, y: 0, width: 0, height: bounds.height), band: .zero)
        }
        let geometry = splitPolicy.columnWidths(container: view.convert(bounds, to: nil), hinge: hinge, gutter: gutter)
        let leading = CGRect(x: 0, y: 0, width: geometry.leadingWidth, height: bounds.height)
        let band = CGRect(x: geometry.leadingWidth, y: 0, width: geometry.bandWidth, height: bounds.height)
        let trailing = CGRect(x: geometry.leadingWidth + geometry.bandWidth, y: 0, width: geometry.trailingWidth, height: bounds.height)
        return Rects(leading: leading, trailing: trailing, band: band, isHinge: geometry.isHinge)
    }

    /// Where column `index` (0 is the root) rests, given `count` entries.
    private func resting(_ index: Int, of count: Int, in rects: Rects) -> CGRect {
        guard isWide else { return index == 0 ? view.bounds : offRight(rects) }
        let left = max(count - 1, 0), right = count
        if index == left { return rects.leading }
        if index == right { return rects.trailing }
        return index < left ? offLeft(rects) : offRight(rects)
    }

    private func offLeft(_ rects: Rects) -> CGRect { rects.leading.offsetBy(dx: -(rects.leading.width + rects.band.width), dy: 0) }
    private func offRight(_ rects: Rects) -> CGRect { CGRect(x: view.bounds.width, y: 0, width: rects.trailing.width, height: view.bounds.height) }

    /// The resting frame of `entry` among `list` (the column after the root), or off to the right when it is not there.
    private func resting(_ entry: FentonColumnEntry, in list: [FentonColumnEntry], rects: Rects) -> CGRect {
        guard let index = list.firstIndex(where: { $0 === entry }) else { return offRight(rects) }
        return resting(index + 1, of: list.count, in: rects)
    }

    private func applyResting() {
        let rects = self.rects
        let count = entries.count
        rootView.frame = resting(0, of: count, in: rects)
        for (offset, entry) in entries.enumerated() { entry.host.frame = resting(offset + 1, of: count, in: rects) }
        if let placeholder, isWide, count == 0 { placeholder.view.frame = rects.trailing }
        let showsBand = isWide && traitCollection.accessibilityContrast == .high && !rects.isHinge
        band.isHidden = !showsBand
        band.frame = rects.band
        band.backgroundColor = showsBand ? .secondaryLabel : .clear
    }

    // MARK: - Width

    /// Sets whether columns show side by side. Turning it off hands the open pages to the navigation stack
    /// (``pushesCollapsedPages``); turning it on brings those pages back as columns.
    public func setWide(_ wide: Bool) {
        guard wide != isWide else { return }
        loadViewIfNeeded()
        isWide = wide
        if wide {
            ensurePlaceholder()
            restoreHandedOffPages()
        } else {
            collapse()
        }
        edgePan?.isEnabled = wide
        refreshState()
        view.setNeedsLayout()
        onWideChange?(wide)
    }

    private func collapse() {
        generation += 1
        openingPending = false
        let locals = entries.filter { $0.tag == nil && $0.pushesWhenNarrow }.map(\.controller)
        for entry in entries { remove(entry) }
        entries = []
        refreshBars()
        removePlaceholder()
        guard pushesCollapsedPages, !locals.isEmpty else { return }
        // After the navigation stack has taken the pages the owner's state holds: the owner reconciles in the same turn as this call.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isWide, let navigation = self.navigationController else { return }
                for page in locals {
                    navigation.pushViewController(page, animated: false)
                }
                self.handedOff = locals
            }
        }
    }

    /// The window splits again: pages this controller pushed when it collapsed leave the stack and come back as columns, unanimated.
    private func restoreHandedOffPages() {
        let pages = handedOff
        handedOff = []
        guard !pages.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isWide, let navigation = self.navigationController else { return }
                let stillPushed = pages.filter { navigation.viewControllers.contains($0) }
                guard !stillPushed.isEmpty else { return }
                navigation.setViewControllers(navigation.viewControllers.filter { page in !stillPushed.contains { $0 === page } }, animated: false)
                self.adopt(stillPushed)
            }
        }
    }

    private func ensurePlaceholder() {
        guard placeholder == nil else { return }
        let page = makePlaceholder()
        page.loadViewIfNeeded()
        addChild(page)
        view.insertSubview(page.view, aboveSubview: rootView)
        page.view.frame = rects.trailing
        page.didMove(toParent: self)
        placeholder = page
    }

    private func removePlaceholder() {
        guard let page = placeholder else { return }
        page.willMove(toParent: nil)
        page.view.removeFromSuperview()
        page.removeFromParent()
        placeholder = nil
    }

    // MARK: - Navigation

    /// How deep `sender` sits: 0 for the root (or anything that is not a hosted page), `n` for the n-th entry.
    public func depth(of sender: Any?) -> Int {
        guard var controller = sender as? UIViewController else { return 0 }
        while true {
            if let index = entries.firstIndex(where: { $0.controller === controller }) { return index + 1 }
            guard let parent = controller.parent else { return 0 }
            controller = parent
        }
    }

    /// The standard UIKit navigation call: a hosted page shows another one. The columns are cut back to the sender's own column and
    /// the page is appended (a drill from the right appends; a tap in the left column replaces what is on the right).
    open override func show(_ vc: UIViewController, sender: Any?) {
        open(vc, tag: nil, atDepth: depth(of: sender))
    }

    open override func showDetailViewController(_ vc: UIViewController, sender: Any?) {
        show(vc, sender: sender)
    }

    /// Opens `page` after cutting the stack back to `depth` (0 keeps only the root).
    /// - Parameters:
    ///   - page: The page to open.
    ///   - tag: What the owner identifies it by; nil for a page only the columns know.
    ///   - depth: How many entries stay.
    ///   - animated: Slide it in; a narrow window never animates here (the navigation stack does).
    ///   - pushesWhenNarrow: Whether the page is pushed on the enclosing navigation stack when the window does not split, or
    ///     dropped (a form the owner re-presents as a sheet).
    ///   - onUserClose: Called when the person closes this page.
    public func open(_ page: UIViewController, tag: AnyHashable?, atDepth depth: Int = 0, animated: Bool = true,
                     pushesWhenNarrow: Bool = true, onUserClose: (() -> Void)? = nil) {
        guard isWide else {
            if pushesWhenNarrow { navigationController?.pushViewController(page, animated: animated) }
            return
        }
        let kept = Array(entries.prefix(max(depth, 0)))
        let entry = makeEntry(page, tag: tag)
        entry.pushesWhenNarrow = pushesWhenNarrow
        entry.onUserClose = onUserClose
        commit(kept + [entry], animated: animated)
    }

    private func makeEntry(_ page: UIViewController, tag: AnyHashable?) -> FentonColumnEntry {
        FentonColumnEntry(controller: page, tag: tag, ground: appearance.ground, hairline: appearance.hairline,
                          displayScale: traitCollection.displayScale)
    }

    /// Takes `page` away if it is the open page on the right (a form its owner closed); nothing happens when something else is.
    public func remove(_ page: UIViewController, animated: Bool = true) {
        guard entries.last?.controller === page else { return }
        commit(Array(entries.dropLast()), animated: animated)
    }

    /// Opens pages that were on the navigation stack (local pages, with no tag) after the tagged entries, unanimated: the window
    /// went from narrow to wide and they keep their place instead of being dropped.
    public func adopt(_ pages: [UIViewController]) {
        guard isWide, !pages.isEmpty else { return }
        commit(entries + pages.map { makeEntry($0, tag: nil) }, animated: false)
    }

    /// A single detail beside the root (an editor, a form), or none: replaces whatever is open. Nothing is kept when the window is
    /// narrow.
    public func setDetail(_ page: UIViewController?, tag: AnyHashable? = nil, animated: Bool = true) {
        guard isWide else { return }
        guard let page else {
            if !entries.isEmpty { commit([], animated: animated) }
            return
        }
        commit([makeEntry(page, tag: tag)], animated: animated)
    }

    /// Brings the tagged pages in line with `tags` (the owner's routes): the common prefix stays, the rest is replaced. A page opened
    /// locally above matching tags stays.
    public func reconcile(tags: [AnyHashable], make: (AnyHashable) -> UIViewController, animated: Bool) {
        guard isWide else { return }
        let current = entries.prefix { $0.tag != nil }.compactMap(\.tag)
        guard current != tags else { return }
        var common = 0
        while common < min(current.count, tags.count), current[common] == tags[common] { common += 1 }
        var next = Array(entries.prefix(common))
        for tag in tags[common...] { next.append(makeEntry(make(tag), tag: tag)) }
        commit(next, animated: animated)
    }

    /// Back: the page on the right goes, the one before it returns to the right. A page that holds itself open (a save in flight,
    /// edits to lose) decides first (``FentonColumnPopGuarding``).
    public func popTop(animated: Bool = true) {
        guard let top = entries.last else { return }
        guarded(top) { [weak self] in
            guard let self, self.entries.last === top else { return }
            self.commit(Array(self.entries.dropLast()), animated: animated)
            self.reportPop([top])
        }
    }

    /// Close: every page goes and the empty state returns.
    public func closeAll(animated: Bool = true) {
        guard let top = entries.last else { return }
        let all = entries
        guarded(top, leaving: all.map(\.controller)) { [weak self] in
            guard let self, self.entries.last === top else { return }
            self.commit([], animated: animated)
            self.reportPop(all)
        }
    }

    /// Runs `proceed` when the open page allows it now, after the discard confirmation, or never (a save in flight).
    private func guarded(_ entry: FentonColumnEntry, leaving: [UIViewController]? = nil, _ proceed: @escaping () -> Void) {
        if let page = entry.controller as? FentonColumnExitRequesting {
            var responded = false
            page.requestColumnExit(leaving: leaving ?? [entry.controller]) { [weak self] in
                guard !responded else { return }
                responded = true
                guard self?.entries.last?.controller === entry.controller else { return }
                proceed()
            }
            return
        }
        switch (entry.controller as? FentonColumnPopGuarding)?.columnPopDecision ?? .allow {
        case .allow:
            proceed()
        case .block:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .confirmDiscard:
            FentonDiscardConfirmation.present(from: entry.controller, copy: appearance.discardCopy, onDiscard: proceed)
        }
    }

    /// The open page's answer to Back and Close changed (a save began or ended, an edit was made): the bar item follows.
    public func pageStateChanged() { refreshBars() }

    private func reportPop(_ removed: [FentonColumnEntry]) {
        for entry in removed { entry.onUserClose?() }
        onUserPop?(entries.prefix { $0.tag != nil }.count)
    }

    // MARK: - Transition

    private func install(_ entry: FentonColumnEntry) {
        addChild(entry.controller)
        view.addSubview(entry.host)
        entry.controller.didMove(toParent: self)
    }

    private func remove(_ entry: FentonColumnEntry) {
        entry.controller.willMove(toParent: nil)
        entry.host.removeFromSuperview()
        entry.controller.removeFromParent()
    }

    /// Runs `animations` as the slide (the standard spring) or, for a fade or under Reduce Motion, over the quick duration.
    private func animate(slides: Bool, _ animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        if slides, !environment.reduceMotion {
            UIView.animate(springDuration: motion.standard.duration, bounce: CGFloat(motion.standard.bounce), initialSpringVelocity: 0,
                           delay: 0, options: [], animations: animations, completion: completion)
        } else {
            UIView.animate(withDuration: motion.quick, delay: 0, options: [.curveEaseInOut], animations: animations, completion: completion)
        }
    }

    /// Replaces the entries and moves the columns: a page that is added with none removed slides in from the right (and the pages
    /// before it slide left); pages removed with none added slide out to the right; added with removed (a different row in the left
    /// column, another item) cross-fades in place. Reduce Motion cross-fades all of them in place: no page that stays on screen
    /// slides, and the edge pan still works.
    ///
    /// **The empty state's order.** Opening the first page: the empty state fades out, and only then does the page come in. Closing
    /// the last page: the page goes out, and only then does the empty state fade in. Replacing or drilling while pages remain never
    /// touches it. The final state always matches `entries.isEmpty`: every commit bumps `generation`, so a fade that was overtaken
    /// by another tap does nothing when it ends, and a commit that changes nothing still settles the empty state.
    private func commit(_ next: [FentonColumnEntry], animated: Bool) {
        let old = entries
        let removed = old.filter { entry in !next.contains { $0 === entry } }
        let added = next.filter { entry in !old.contains { $0 === entry } }
        guard !removed.isEmpty || !added.isEmpty else {
            settlePlaceholder()
            return
        }
        generation += 1
        openingPending = false
        let gen = generation
        let animate = animated && isWide && view.window != nil
        if animate, old.isEmpty, !next.isEmpty, let placeholder, placeholder.view.alpha > 0.01 {
            openingPending = true
            self.animate(slides: false, { placeholder.view.alpha = 0 }, completion: { [weak self] _ in
                guard let self, self.generation == gen else { return }
                self.openingPending = false
                self.transition(to: next, animate: true)
            })
            return
        }
        transition(to: next, animate: animate)
    }

    /// Fades the empty state in when nothing is open and nothing is about to be.
    private func fadeInPlaceholder() {
        guard let placeholder, isWide, entries.isEmpty, !openingPending else { return }
        placeholder.view.isHidden = false
        guard placeholder.view.alpha < 1 else { return }
        animate(slides: false) { placeholder.view.alpha = 1 }
    }

    /// A commit that changes nothing: if it overtook a pending opening, the empty state comes back.
    private func settlePlaceholder() {
        if openingPending {
            generation += 1
            openingPending = false
        }
        if animations == 0 { fadeInPlaceholder() }
    }

    private func transition(to next: [FentonColumnEntry], animate: Bool) {
        let old = entries
        let removed = old.filter { entry in !next.contains { $0 === entry } }
        let added = next.filter { entry in !old.contains { $0 === entry } }
        guard !removed.isEmpty || !added.isEmpty else { return }
        let reduce = environment.reduceMotion
        let fades = !removed.isEmpty && !added.isEmpty || reduce
        view.layoutIfNeeded()
        if next.isEmpty || old.isEmpty { ensurePlaceholder() }
        // Closing the last page: the empty state waits (invisible) until the page has gone, then fades in (``fadeInPlaceholder``).
        if next.isEmpty { placeholder?.view.alpha = animate ? 0 : 1 }
        let before = rects
        for entry in added { install(entry) }
        entries = next
        refreshBars()
        let after = rects
        if animate {
            for entry in added {
                entry.host.frame = fades ? resting(entry, in: next, rects: after) : offRight(after)
                entry.host.alpha = fades ? 0 : 1
            }
            for entry in removed { entry.host.frame = resting(entry, in: old, rects: before) }
            // The pages in the window are laid out at their destination first, so their content does not resize mid-slide.
            if let placeholder, next.isEmpty { placeholder.view.frame = after.trailing }
        } else {
            for entry in added { entry.host.alpha = 1 }
        }
        let finish = { [weak self] in
            guard let self else { return }
            for entry in removed { self.remove(entry) }
            if !self.entries.isEmpty { self.removePlaceholder() }
            self.refreshState()
            self.fadeInPlaceholder()
            self.view.setNeedsLayout()
            self.onSettled?()
        }
        guard animate else {
            for entry in removed { remove(entry) }
            if !entries.isEmpty { removePlaceholder() }
            applyResting()
            refreshState()
            return
        }
        // Reduce Motion: a page that stays on screen does not slide. One whose column changes jumps to its new column and
        // cross-fades in place with a snapshot of where it was; only opacity animates.
        var crossFading: [UIView] = []
        if reduce {
            let rects = self.rects
            var survivors = [(view: rootView, frame: resting(0, of: next.count, in: rects))]
            for (offset, entry) in next.enumerated() where !added.contains(where: { $0 === entry }) {
                survivors.append((entry.host, resting(offset + 1, of: next.count, in: rects)))
            }
            for survivor in survivors where survivor.view.frame != survivor.frame {
                if let snapshot = survivor.view.snapshotView(afterScreenUpdates: false) {
                    snapshot.frame = survivor.view.frame
                    snapshot.isUserInteractionEnabled = false
                    snapshot.accessibilityElementsHidden = true
                    view.addSubview(snapshot)
                    crossFading.append(snapshot)
                }
                survivor.view.frame = survivor.frame
                survivor.view.alpha = 0
            }
        }
        animations += 1
        let fading = crossFading
        let moves = { [self] in
            if reduce {
                rootView.alpha = 1
                fading.forEach { $0.alpha = 0 }
            }
            let rects = self.rects
            self.rootView.frame = self.resting(0, of: next.count, in: rects)
            for (offset, entry) in next.enumerated() {
                entry.host.frame = self.resting(offset + 1, of: next.count, in: rects)
                if fades { entry.host.alpha = 1 }
            }
            for entry in removed {
                if fades { entry.host.alpha = 0 } else { entry.host.frame = self.offRight(rects) }
            }
        }
        self.animate(slides: !fades, moves, completion: { [weak self] _ in
            fading.forEach { $0.removeFromSuperview() }
            guard let self else { return }
            self.animations -= 1
            if self.animations == 0 { finish() } else { for entry in removed { self.remove(entry) } }
            self.refreshState()
        })
    }

    // MARK: - Bars

    /// The column group of the section's bar: the open page's own bar items, then Back (a drilled page) or Close (the first page).
    /// Empty (nothing open, or a narrow window) takes the group away.
    private func refreshBars() {
        pageItemsObservation = []
        guard isWide, let top = entries.last, !top.drawsOwnChrome else {
            columnBarHost?.setColumnItems([])
            return
        }
        let item = top.controller.navigationItem
        let changed: @Sendable (UINavigationItem, NSKeyValueObservedChange<[UIBarButtonItem]?>) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshBars() } }
        }
        pageItemsObservation = [item.observe(\.rightBarButtonItems, changeHandler: changed),
                                item.observe(\.leftBarButtonItems, changeHandler: changed)]
        // The page's own bar items, leading then trailing, ride in the column group.
        let own = (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? [])
        let single = entries.count == 1
        let blocked = (top.controller as? FentonColumnPopGuarding)?.columnPopDecision == .block
        exitItem.image = UIImage(systemName: single ? "xmark" : "chevron.backward")
        exitItem.accessibilityLabel = single ? appearance.closeLabel : appearance.backLabel
        exitItem.accessibilityIdentifier = single ? "column.close" : "column.back"
        exitItem.isEnabled = !blocked
        exitAction = { [weak self] in
            if single { self?.closeAll() } else { self?.popTop() }
        }
        columnBarHost?.setColumnItems(own + [exitItem])
    }

    /// The nearest ancestor that owns a bar to put the column group on.
    private var columnBarHost: FentonColumnBarHosting? {
        var controller = parent
        while let current = controller {
            if let host = current as? FentonColumnBarHosting { return host }
            controller = current.parent
        }
        return nil
    }

    /// The Back or Close item the columns hand to the bar host, so a test or an app can reach it.
    public var exitBarItem: UIBarButtonItem { exitItem }

    /// VoiceOver sees only the columns in the window, and the edge pan works only with a page to go back from.
    private func refreshState() {
        refreshBars()
        let count = entries.count
        let left = max(count - 1, 0)
        rootView.accessibilityElementsHidden = isWide && 0 < left
        for (offset, entry) in entries.enumerated() {
            let visible = offset + 1 >= left
            entry.host.accessibilityElementsHidden = !visible
            entry.host.accessibilityIdentifier = offset == count - 1 ? trailingIdentifier : nil
        }
        placeholder?.view.accessibilityElementsHidden = !entries.isEmpty
        placeholder?.view.isHidden = !entries.isEmpty && animations == 0
        edgePan?.isEnabled = takesEdgePan
    }

    // MARK: - Interactive back

    /// A drag from the screen's leading edge scrubs Back: the right column follows the finger off to the right while the pages
    /// before it return, and lifting past halfway (or with speed) completes it.
    @objc private func edgePanned(_ pan: UIScreenEdgePanGestureRecognizer) {
        handleEdgePan(state: pan.state, translation: pan.translation(in: view).x, velocity: pan.velocity(in: view).x)
    }

    /// The edge pan's behaviour for one state of the gesture (a recognizer's own state cannot be set, so a hosted test drives this).
    public func handleEdgePan(state: UIGestureRecognizer.State, translation: CGFloat, velocity: CGFloat) {
        // Under Reduce Motion the swipe still works: the pages follow the finger, a direct manipulation.
        guard isWide, !entries.isEmpty else { return }
        // A page that holds itself open (a save, edits to lose) is left with Back or Close, not by a drag.
        if state == .began, let guarded = entries.last?.controller as? FentonColumnPopGuarding, guarded.columnPopDecision != .allow { return }
        let width = max(view.bounds.width, 1)
        switch state {
        case .began:
            beginBackScrub()
        case .changed:
            backAnimator?.fractionComplete = min(max(translation / width, 0), 1)
        case .ended, .cancelled, .failed:
            guard let animator = backAnimator else { return }
            let completes = state == .ended && (animator.fractionComplete > 0.5 || velocity > 600)
            animator.isReversed = !completes
            animator.startAnimation()
        default:
            break
        }
    }

    private func beginBackScrub() {
        let old = entries
        let next = Array(entries.dropLast())
        guard let top = old.last, backAnimator == nil else { return }
        if let page = top.controller as? FentonColumnExitRequesting {
            var asking = true, approved = false, responded = false
            page.requestColumnExit(leaving: [top.controller]) { [weak self] in
                guard !responded else { return }
                responded = true
                guard let self, self.isWide, self.entries.last === top else { return }
                if asking {
                    approved = true
                } else {
                    self.commit(next, animated: true)
                    self.reportPop([top])
                }
            }
            asking = false
            guard approved else { return }
        }
        if next.isEmpty {
            ensurePlaceholder()
            placeholder?.view.alpha = 0
        }
        view.layoutIfNeeded()
        let animator = UIViewPropertyAnimator(duration: motion.standard.duration, curve: .easeOut) { [self] in
            let after = rects
            rootView.frame = resting(0, of: next.count, in: after)
            for (offset, entry) in next.enumerated() { entry.host.frame = resting(offset + 1, of: next.count, in: after) }
            top.host.frame = offRight(after)
        }
        animations += 1
        animator.pauseAnimation()
        animator.addCompletion { [weak self] position in
            guard let self else { return }
            self.animations -= 1
            if position == .end {
                self.entries = next
                self.remove(top)
                if !self.entries.isEmpty { self.removePlaceholder() }
                self.reportPop([top])
            }
            self.backAnimator = nil
            self.refreshState()
            self.fadeInPlaceholder()
            self.view.setNeedsLayout()
            self.onSettled?()
        }
        backAnimator = animator
    }
}
#endif
