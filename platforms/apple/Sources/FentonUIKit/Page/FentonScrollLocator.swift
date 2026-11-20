#if os(iOS)
import UIKit

/// Finds the scroll view a page is about: the fallback for a page that does not name its own (a second tap on the selected tab, or
/// a ``FentonPageHost`` that wraps a plain controller).
@MainActor
public enum FentonScrollLocator {
    /// The largest visible vertical scroll view under `root`.
    ///
    /// A candidate must be on screen (in a window, not hidden, not transparent), show at least 200 by 200 points inside the window,
    /// and be scrollable (content taller than the view, or `alwaysBounceVertical`). Small scrollers (a carousel, a picker) are
    /// not the page's.
    /// - Parameter root: The view to search; it must be in a window.
    /// - Returns: The candidate with the largest visible area; nil when none qualifies.
    public static func mainScrollView(in root: UIView) -> UIScrollView? {
        guard let window = root.window else { return nil }
        var best: (view: UIScrollView, area: CGFloat)?
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            guard let scroll = view as? UIScrollView, !scroll.isHidden, scroll.alpha > 0.01 else { continue }
            let visible = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
            guard visible.width > 200, visible.height > 200,
                  scroll.contentSize.height > scroll.bounds.height + 1 || scroll.alwaysBounceVertical else { continue }
            let area = visible.width * visible.height
            if area > (best?.area ?? 0) { best = (scroll, area) }
        }
        return best?.view
    }
}
#endif
