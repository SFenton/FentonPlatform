#if os(iOS)
import UIKit

/// The colours and words of the columns, all optional: the app passes its own, the columns add none.
///
/// FentonPlatform ships no localisation resources: the default words are developer English so a bare fixture reads, and every one
/// is a public value an app overrides with its own localised copy.
public struct FentonColumnsAppearance {
    /// A colour under every page that paints none of its own; nil leaves the page's own background (clear).
    public var ground: UIColor?
    /// A one-pixel separator on the leading edge of each open page; nil draws none.
    public var hairline: UIColor?
    /// The Back item's accessibility label. Developer English by default; the app supplies localised copy.
    public var backLabel = "Back"
    /// The Close item's accessibility label. Developer English by default; the app supplies localised copy.
    public var closeLabel = "Close"
    /// The words of the confirmation a page with ``FentonColumnPopDecision/confirmDiscard`` raises.
    public var discardCopy = FentonDiscardCopy()

    /// Creates an appearance with no colours and the neutral words.
    public init() {}
}
#endif
