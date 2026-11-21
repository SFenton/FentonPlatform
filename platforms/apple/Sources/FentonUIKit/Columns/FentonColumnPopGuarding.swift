#if os(iOS)
import UIKit

/// Whether a page lets Back or Close take it away (``FentonColumnPopGuarding``).
public enum FentonColumnPopDecision: Equatable, Sendable {
    /// Back and Close proceed.
    case allow
    /// A save is in flight: Back and Close are off and the edge pan does not start.
    case block
    /// Edits would be lost: Back and Close ask first (``FentonDiscardConfirmation``).
    case confirmDiscard
}

/// A page in a column that can hold itself open: while it saves (``FentonColumnPopDecision/block``) or has edits to lose
/// (``FentonColumnPopDecision/confirmDiscard``). The page calls ``FentonColumnsViewController/pageStateChanged()`` when its answer
/// changes.
@MainActor
public protocol FentonColumnPopGuarding: AnyObject {
    /// The page's answer to Back and Close right now.
    var columnPopDecision: FentonColumnPopDecision { get }
}

/// A page that does its own asking before a column leaves, for a draft that needs its own discard or release step. The columns call
/// ``requestColumnExit(leaving:completion:)`` instead of consulting ``FentonColumnPopGuarding/columnPopDecision``; calling
/// `completion` approves the exit, never calling it keeps the page open.
@MainActor
public protocol FentonColumnExitRequesting: FentonColumnPopGuarding {
    /// Asks whether the page (and the other pages in `leaving`) may go.
    /// - Parameters:
    ///   - leaving: The controllers that would leave, the asking page last.
    ///   - completion: Approves the exit. Only the first call counts.
    func requestColumnExit(leaving: [UIViewController], completion: @escaping () -> Void)
}

/// Anything that owns a navigation bar and can show the columns' group of bar items beside its own: the section page above a
/// ``FentonColumnsViewController``. The columns find it by walking up their parents.
@MainActor
public protocol FentonColumnBarHosting: AnyObject {
    /// Sets the column group: the open page's own bar items, then Back (a drilled page) or Close (the first page). An empty array
    /// takes the group away (nothing is open, or the window shows no columns). The host places it, usually as a separate trailing
    /// group the Duo's vertical bar shows apart.
    func setColumnItems(_ items: [UIBarButtonItem])
}
#endif
