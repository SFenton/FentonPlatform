#if os(iOS)
import UIKit

/// The colours and words of the columns, all optional: the app passes its own, the columns add none.
public struct FentonColumnsAppearance {
    /// A colour under every page that paints none of its own; nil leaves the page's own background (clear).
    public var ground: UIColor?
    /// A one-pixel separator on the leading edge of each open page; nil draws none.
    public var hairline: UIColor?
    /// The Back item's accessibility label.
    public var backLabel = "Back"
    /// The Close item's accessibility label.
    public var closeLabel = "Close"
    /// The words of the confirmation a page with ``FentonColumnPopDecision/confirmDiscard`` raises.
    public var discardCopy = FentonDiscardCopy()

    /// Creates an appearance with no colours and the neutral words.
    public init() {}
}
#endif
