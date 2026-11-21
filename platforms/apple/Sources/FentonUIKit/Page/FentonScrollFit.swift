#if os(iOS)
import ObjectiveC
import UIKit

/// A page scrolls only once its content outgrows it, and never sideways.
///
/// A scroll view that fits its content neither bounces nor answers a drag, so a short page does not stretch and snap back. The
/// decision is geometry, never a device check. ``FentonPageViewController/setPageScrollView(_:)`` applies it to the page's scroll
/// view.
@MainActor
public enum FentonScrollFit {
    // MARK: - Vertical

    /// Applies the rule to a vertical scroll view. `UIScrollView` bounces vertically only when its content is taller than the view
    /// while `alwaysBounceVertical` is off, which is the rule; `UICollectionView` and `UITableView` default it on in some
    /// configurations, so it is switched off here. Also pins the width (``pinWidth(of:)``).
    public static func apply(to scrollView: UIScrollView) {
        scrollView.alwaysBounceVertical = false
        pinWidth(of: scrollView)
    }

    /// The exception: a scroll view that pulls to refresh always bounces.
    public static func allowsPullToRefresh(_ scrollView: UIScrollView) {
        scrollView.alwaysBounceVertical = true
    }

    // MARK: - Horizontal

    /// A page body never scrolls sideways: no horizontal bounce or indicator, and any horizontal offset a layout transient leaves
    /// is put back at once. The width of the content itself is the page's to pin to the frame (`contentLayoutGuide` width equal to
    /// `frameLayoutGuide` width, or a frame-set content size of the frame's width); this is the backstop that makes it impossible
    /// for a page to forget.
    ///
    /// The offset observation writes only when the offset is more than half a point from rest, so a vertical scroll costs no
    /// write. Calling it twice on one scroll view installs one observation.
    public static func pinWidth(of scrollView: UIScrollView) {
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.isDirectionalLockEnabled = true
        guard objc_getAssociatedObject(scrollView, &Keys.lock) == nil else { return }
        let token = scrollView.observe(\.contentOffset, options: [.new]) { scroll, _ in
            MainActor.assumeIsolated {
                let rest = -scroll.adjustedContentInset.left
                if abs(scroll.contentOffset.x - rest) > 0.5 { scroll.contentOffset.x = rest }
            }
        }
        objc_setAssociatedObject(scrollView, &Keys.lock, token, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    // MARK: - Keys

    private enum Keys {
        nonisolated(unsafe) static var lock: UInt8 = 0
    }
}
#endif
