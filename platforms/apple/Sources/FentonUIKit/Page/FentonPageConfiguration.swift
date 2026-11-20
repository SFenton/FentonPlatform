#if os(iOS)
import CoreGraphics
import FentonAppleCore

/// The ground a ``FentonPageViewController`` sits on.
public enum FentonPageSurface: Sendable, Equatable {
    /// A page of the app: transparent, so whatever the window draws behind it (a wallpaper, a backdrop) shows through and a push, pop
    /// or split moves content over a ground that never moves.
    case page
    /// A page in a sheet: the system's grouped ground, an inline title, and a header fade that is not capped.
    case sheet
}

/// What a ``FentonPageViewController`` is asked to do. Values only: the app chooses, the page applies.
public struct FentonPageConfiguration: Sendable, Equatable {
    /// The ground the page sits on.
    public var surface: FentonPageSurface = .page
    /// How the title is drawn. A sheet always draws an inline title.
    public var titleStyle: FentonTitleStyle = .large
    /// Whether content fades out under the header. On iOS 26 and later this is the system's soft top edge effect; before it, a
    /// gradient mask on ``FentonPageViewController/contentView`` (``FentonHeaderEdgeFade``).
    public var edgeFade: Bool = true
    /// Height of the fade ramp below the header (see ``FentonScrollEdgeFade/rampHeight``).
    public var edgeRampHeight: CGFloat = FentonScrollEdgeFade.rampHeight
    /// Point size of the ``FentonTitleStyle/fixedInline`` title at the default text size.
    public var fixedTitlePointSize: CGFloat = 24
    /// The largest point size the ``FentonTitleStyle/fixedInline`` title grows to with Dynamic Type.
    public var fixedTitleMaximumPointSize: CGFloat = 30

    /// Creates the default configuration: a page on the app's ground, large title, edge fade on.
    public init() {}
}
#endif
