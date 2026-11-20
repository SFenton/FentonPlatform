#if os(iOS)
import UIKit

/// One page in a column stack: the controller, the host view that slides, and what the owner tagged it with.
///
/// The host is created once and only ever moved by frame: the page's view is added to it once and never reparented, so a slide,
/// a fold or a rotation never reloads or blinks the page. The page has no header here: its title is content
/// (``FentonColumnTitleHeader``) and Back or Close are bar items of the section's own bar (``FentonColumnBarHosting``).
@MainActor
public final class FentonColumnEntry {
    // MARK: - Properties

    /// The page.
    public let controller: UIViewController
    /// What the owner identifies this page by (a route, an id); nil for a local push (``UIViewController/show(_:sender:)``).
    public let tag: AnyHashable?
    /// The view that slides; the page's view is its only content (plus an optional hairline).
    public let host = UIView()
    /// Whether this page goes onto the enclosing navigation stack when the window stops splitting. A form the owner re-presents as a
    /// sheet says no.
    public var pushesWhenNarrow = true
    /// Called when the person closes this page (Back, Close, the edge pan), not when the owner removes it.
    public var onUserClose: (() -> Void)?

    /// A page that is a navigation controller draws its own bar: no column group for it.
    var drawsOwnChrome: Bool { controller is UINavigationController }

    // MARK: - Creating

    /// - Parameters:
    ///   - controller: The page.
    ///   - tag: What the owner identifies it by.
    ///   - ground: A colour under the page when it paints none of its own.
    ///   - hairline: A one-pixel separator colour on the page's leading edge; nil draws none.
    ///   - displayScale: Points per pixel for the hairline.
    init(controller: UIViewController, tag: AnyHashable?, ground: UIColor?, hairline: UIColor?, displayScale: CGFloat) {
        self.controller = controller
        self.tag = tag
        host.clipsToBounds = true
        host.backgroundColor = ground ?? .clear
        host.isOpaque = false
        controller.loadViewIfNeeded()
        controller.view.frame = host.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(controller.view)
        if let hairline {
            let line = UIView()
            line.backgroundColor = hairline
            line.isAccessibilityElement = false
            line.frame = CGRect(x: 0, y: 0, width: 1 / max(displayScale, 1), height: host.bounds.height)
            line.autoresizingMask = [.flexibleHeight, .flexibleRightMargin]
            host.addSubview(line)
        }
    }
}
#endif
