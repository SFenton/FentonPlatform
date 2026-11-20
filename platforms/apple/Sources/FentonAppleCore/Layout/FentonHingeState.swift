/// A folding phone's hinge status, platform-neutral so policies test on the macOS host.
public enum FentonHingeState: Sendable, Hashable {
    /// Folded shut (the outer display).
    case closed
    /// Partly folded (book pose).
    case partiallyOpen
    /// Lying flat.
    case fullyOpen
}
