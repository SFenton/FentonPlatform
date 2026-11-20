#if os(iOS)
import UIKit

/// A navigation controller that lets the app admit each pop before UIKit changes the stack: Back, the ancestor menu
/// (`popToViewController`), `popToRootViewController` and the edge swipe of ``FentonStackMotion``.
///
/// The app sets ``requestPop``. It receives the controllers that would leave and a completion; calling the completion approves the
/// pop, never calling it (or calling it after the stack has moved on) cancels it. A deferred approval becomes a normal pop, and
/// a stale or repeated approval does nothing. Without ``requestPop`` this is a plain `UINavigationController`.
///
/// **The swipe.** UIKit's own edge swipe (`interactivePopGestureRecognizer`) and, on iOS 26, its content swipe never call
/// `popViewController(animated:)`, so they cannot be admitted. While ``requestPop`` is set this controller keeps both from
/// beginning; install ``FentonStackMotion`` to get an edge swipe that pops through ``popViewController(animated:)`` and so goes
/// through the same admission. With no ``requestPop`` the system swipes work as UIKit ships them.
@MainActor
open class FentonNavigationController: UINavigationController, UIGestureRecognizerDelegate {
    // MARK: - Admission

    /// Asks the app whether the controllers in the first argument may leave; the second argument is the approval.
    ///
    /// The closure runs before the stack changes. It may call the approval at once (no dialog), later (after a confirmation), or
    /// never.
    public var requestPop: (([UIViewController], @escaping () -> Void) -> Void)? {
        didSet { refreshSystemSwipes() }
    }

    private var approvingPop = false

    // MARK: - Lifecycle

    open override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        refreshSystemSwipes()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshSystemSwipes()
    }

    // MARK: - System swipes

    /// UIKit's content swipe (iOS 26) has no delegate of ours to ask, so it is switched off while a pop must be admitted. It is only
    /// ever switched off here: an app or ``FentonStackMotion`` may have switched it off for its own reasons.
    private func refreshSystemSwipes() {
        guard #available(iOS 26.0, *), isViewLoaded, requestPop != nil,
              let content = interactiveContentPopGestureRecognizer, content.isEnabled else { return }
        content.isEnabled = false
    }

    /// The edge swipe begins only on a page that has a Back to go to, only when no admission is required, and never while another
    /// transition runs (a swipe during a push or pop would corrupt the stack).
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        guard requestPop == nil, viewControllers.count > 1, transitionCoordinator == nil else { return false }
        return topViewController?.navigationItem.hidesBackButton != true
    }

    // MARK: - Pops

    open override func popViewController(animated: Bool) -> UIViewController? {
        guard !approvingPop, viewControllers.count > 1, let requestPop else { return super.popViewController(animated: animated) }
        let expected = topViewController
        var result: UIViewController?
        var responded = false
        requestPop(Array(viewControllers.suffix(1))) { [weak self, weak expected] in
            guard !responded else { return }
            responded = true
            guard let self, let expected, self.topViewController === expected else { return }
            result = self.approvedPop(animated: animated)
        }
        return result
    }

    open override func popToViewController(_ target: UIViewController, animated: Bool) -> [UIViewController]? {
        guard !approvingPop, topViewController !== target, let index = viewControllers.firstIndex(of: target), let requestPop else {
            return super.popToViewController(target, animated: animated)
        }
        let expected = topViewController
        var result: [UIViewController]?
        var responded = false
        requestPop(Array(viewControllers.dropFirst(index + 1))) { [weak self, weak expected, weak target] in
            guard !responded else { return }
            responded = true
            guard let self, let expected, let target, self.topViewController === expected,
                  self.viewControllers.contains(target) else { return }
            result = self.approvedPop(to: target, animated: animated)
        }
        return result
    }

    open override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        guard let root = viewControllers.first else { return nil }
        return popToViewController(root, animated: animated)
    }

    private func approvedPop(animated: Bool) -> UIViewController? {
        approvingPop = true
        defer { approvingPop = false }
        return super.popViewController(animated: animated)
    }

    private func approvedPop(to target: UIViewController, animated: Bool) -> [UIViewController]? {
        approvingPop = true
        defer { approvingPop = false }
        return super.popToViewController(target, animated: animated)
    }
}
#endif
