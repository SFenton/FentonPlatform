import CoreGraphics

/// A folding phone's hinge as the window sees it, in either pose of the inner display.
///
/// | Pose | ``hinge`` | ``isFolding`` | ``band`` | Page division |
/// |---|---|---|---|---|
/// | Partly folded (book pose) | the division region | true | the hinge | on the hinge: the leading side ends at the band, the trailing side starts after it |
/// | Lying flat | the division region (reported inactive) | false | nil | the midpoint of the free space (the window less the trailing rail), 1 pt |
/// | Folded outer screen, phone, tablet | nil | false | nil | the midpoint (tablet) or none |
///
/// Content keeps clear of ``band`` only: while the device lies flat nothing avoids the hinge, so a row of like tiles has no gap
/// in the middle and a centred object centres in the free space. Presence (the shell's style, where sheets go, whether they
/// fill the height) reads ``hinge``, which is set in both poses. Derive it from the same reserved regions: the active division
/// region while partly folded, else the inactive one.
public struct FentonWindowFold: Equatable, Sendable {
    // MARK: - Values

    /// The hinge's division region in window coordinates, in either pose; nil without one (and on the folded outer screen).
    public var hinge: CGRect? {
        didSet { if hinge == nil { isFolding = false } }
    }

    /// The inner display is partly folded: the division region is active. Forced false while ``hinge`` is nil.
    public var isFolding: Bool {
        didSet { if hinge == nil { isFolding = false } }
    }

    /// Creates a fold. `isFolding` is ignored (false) when `hinge` is nil.
    public init(hinge: CGRect?, isFolding: Bool) {
        self.hinge = hinge
        self.isFolding = isFolding && hinge != nil
    }

    /// No hinge visible.
    public static let none = FentonWindowFold(hinge: nil, isFolding: false)

    // MARK: - Derived

    /// The band content keeps clear of: the hinge while partly folded; nil while flat or without a hinge.
    public var band: CGRect? { isFolding ? hinge : nil }

    /// The hinge runs top to bottom (landscape, either pose).
    public var isVertical: Bool { hinge.map { $0.height > $0.width } ?? false }
}
