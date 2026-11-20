#if os(iOS)
import UIKit

/// The title of a page that is shown in a column (``FentonColumnsViewController``): a large, left-aligned heading at the top of the
/// page's content, in the style of the system large title, that scrolls away with the content. The section's bar spans both columns
/// and carries the page header, so a column page never sets a bar title; one component serves every column page.
///
/// The page's top additional safe area makes room for the heading, so every page body (a scroll view the system insets, or a short
/// page that lays out from the safe area) starts below it. The heading is a subview of the page's content, parked in that room and
/// moved up with the scroll view's offset (and faded as it goes, so it never crosses the header). Its height depends only on the
/// text style, so nothing here feeds layout.
///
/// A page attaches it while it is a child of the columns and detaches it when it is pushed on a navigation stack, where the bar
/// shows the title instead:
///
/// ```swift
/// override func didMove(toParent parent: UIViewController?) {
///     super.didMove(toParent: parent)
///     if parent is FentonColumnsViewController, let scroll = contentScrollView {
///         columnTitle.attach(to: scroll, in: self, host: contentView, title: title)
///     } else {
///         columnTitle.detach()
///     }
/// }
/// ```
@MainActor
public final class FentonColumnTitleHeader: UILabel {
    // MARK: - State

    private weak var scroll: UIScrollView?
    private weak var page: UIViewController?
    private var reserved: CGFloat = 0
    private var offsetObservation: NSKeyValueObservation?
    private let sideInset: CGFloat
    private let spacing: CGFloat

    // MARK: - Creating

    /// - Parameters:
    ///   - sideInset: The heading's inset from the content's leading and trailing edges.
    ///   - spacing: The room under the heading's line.
    public init(sideInset: CGFloat = 16, spacing: CGFloat = 8) {
        self.sideInset = sideInset
        self.spacing = spacing
        super.init(frame: .zero)
        let base = UIFont.preferredFont(forTextStyle: .largeTitle)
        font = UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor, size: 0)
        adjustsFontForContentSizeCategory = true
        textColor = .label
        adjustsFontSizeToFitWidth = true
        minimumScaleFactor = 0.6
        accessibilityTraits = .header
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var height: CGFloat { ceil(font.lineHeight) + spacing }

    // MARK: - Attaching

    /// Puts the heading in `host` (the page's content view), tracking `scroll`, with `title` as its text. Attaching again to the
    /// same scroll view only updates the text.
    public func attach(to scroll: UIScrollView, in page: UIViewController, host: UIView, title: String?) {
        text = title
        isHidden = title == nil
        guard self.scroll !== scroll else {
            place()
            return
        }
        detach()
        self.scroll = scroll
        self.page = page
        reserved = height
        page.additionalSafeAreaInsets.top += reserved
        host.addSubview(self)
        offsetObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.place() }
        }
        place()
    }

    /// Takes the heading and its room away.
    public func detach() {
        guard scroll != nil else { return }
        offsetObservation = nil
        page?.additionalSafeAreaInsets.top -= reserved
        reserved = 0
        removeFromSuperview()
        scroll = nil
        page = nil
    }

    /// Parks the heading in its room and moves it with the scroll offset (call from the page's layout; it writes no inset).
    public func place() {
        guard let scroll, let page, let host = superview, reserved > 0 else { return }
        let scrolled = max(0, scroll.contentOffset.y + scroll.adjustedContentInset.top)
        let top = page.view.safeAreaInsets.top - reserved
        frame = CGRect(x: sideInset, y: top - scrolled, width: max(0, host.bounds.width - 2 * sideInset), height: reserved)
        alpha = max(0, 1 - scrolled / reserved)
    }
}
#endif
