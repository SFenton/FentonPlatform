#if os(iOS)
import UIKit

/// The bar buttons a page shows, as its app answers them from ``FentonPageViewController/barItems()``.
///
/// The foundation owns no chrome: no quick links, no profile, no menu. An app subclasses the page, builds its own
/// `UIBarButtonItem`s and returns them here; the page writes them to its `navigationItem` only when they changed.
public struct FentonBarItems {
    /// Items on the leading side, leading-most first (`leftBarButtonItems`).
    public var leading: [UIBarButtonItem]
    /// Items on the trailing side, trailing-most first (`rightBarButtonItems`).
    public var trailing: [UIBarButtonItem]

    /// Creates a set of bar items; both sides are empty by default.
    public init(leading: [UIBarButtonItem] = [], trailing: [UIBarButtonItem] = []) {
        self.leading = leading
        self.trailing = trailing
    }
}
#endif
