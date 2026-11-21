#if os(iOS)
import Foundation

/// How a ``FentonPageViewController`` draws its title.
public enum FentonTitleStyle: Sendable, Equatable {
    /// The system's large title below the bar, collapsing into the inline title as the page scrolls. Where the window shows a
    /// vertical bar (``FentonWindowEnvironment/inVerticalBar``: the folded Duo's rail) the bar never has room for a large title, so
    /// the page uses the ``fixedInline`` treatment there instead.
    case large
    /// The system's inline title in every window.
    case inline
    /// A fixed inline title that never minimises: a semibold title at ``FentonPageConfiguration/fixedTitlePointSize`` (Dynamic
    /// Type, capped at ``FentonPageConfiguration/fixedTitleMaximumPointSize``). It is what a vertical bar needs, so the title
    /// is not taken away when the page scrolls; ``FentonFixedBarTitle`` writes it.
    case fixedInline
}
#endif
