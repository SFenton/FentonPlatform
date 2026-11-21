#if os(iOS)
import UIKit

/// The one way a controller puts a child controller's view inside its own: `addChild`, pin, `didMove`, and the status-bar update
/// that follows. A parent that hosts a child (a page host, a root, a swap container) calls this instead of repeating the three
/// containment calls, so every host gets the same order, the same pinning and the same status-bar behaviour.
///
/// **Status bar.** Embedding or removing a child asks the parent to refresh its status bar (`setNeedsStatusBarAppearanceUpdate`),
/// but UIKit only reads the child's style if the parent says so: a parent that wants the child's style overrides
/// `childForStatusBarStyle` and `childForStatusBarHidden` to return it (``FentonPageHost`` does).
@MainActor
public enum FentonEmbedding {
    // MARK: - Embed and remove

    /// Where the child's view goes among its container's subviews.
    public enum Position {
        /// Over every other subview.
        case front
        /// Under every other subview.
        case back
        /// Directly under `view`, which must be a subview of the container.
        case below(UIView)
        /// Directly over `view`, which must be a subview of the container.
        case above(UIView)
    }

    /// Embeds `child` in `parent`, filling `container` (the parent's view by default).
    ///
    /// Idempotent: a child already embedded in the same parent and container is left as it is, so a host may call it from every
    /// update. A child that sits in another parent is removed from it first.
    /// - Parameters:
    ///   - child: The controller to embed.
    ///   - parent: The controller that owns it.
    ///   - container: The view of `parent` the child fills; `parent.view` when nil.
    ///   - insets: Constant insets from the container's edges.
    ///   - position: Where the child's view goes among the container's subviews; over the others by default.
    public static func embed(_ child: UIViewController, in parent: UIViewController, container: UIView? = nil,
                             insets: UIEdgeInsets = .zero, position: Position = .front) {
        guard let host = container ?? parent.view else { return }
        if child.parent === parent, child.view.superview === host { return }
        if child.parent != nil { remove(child) }
        parent.addChild(child)
        switch position {
        case .front: host.addSubview(child.view)
        case .back: host.insertSubview(child.view, at: 0)
        case let .below(view): host.insertSubview(child.view, belowSubview: view)
        case let .above(view): host.insertSubview(child.view, aboveSubview: view)
        }
        pin(child.view, to: host, insets: insets)
        child.didMove(toParent: parent)
        parent.setNeedsStatusBarAppearanceUpdate()
    }

    /// Removes `child` from its parent: `willMove`, view out, `removeFromParent`, then the parent's status bar is refreshed.
    /// Does nothing for a controller that has no parent.
    public static func remove(_ child: UIViewController) {
        guard let parent = child.parent else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
        parent.setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Pinning

    /// Pins `view`'s four edges to `container`'s, offset by `insets`, and turns off autoresizing-mask constraints on `view`.
    /// - Returns: The four constraints (leading, trailing, top, bottom), active.
    @discardableResult
    public static func pin(_ view: UIView, to container: UIView, insets: UIEdgeInsets = .zero) -> [NSLayoutConstraint] {
        view.translatesAutoresizingMaskIntoConstraints = false
        let constraints = [
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -insets.bottom),
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }
}
#endif
