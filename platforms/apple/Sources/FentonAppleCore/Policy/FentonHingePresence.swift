/// Remembers, for the life of the process, that this device has a hinge, and tells its owner the first time one is seen.
///
/// The folded outer screen reports no hinge region, so this memory is what tells it from a phone without one. Later nil values
/// never clear it. The UIKit layer passes `onFirstHinge` to ask the system to re-read supported orientations; this type holds no
/// UIKit.
@MainActor
public final class FentonHingePresence {
    /// Process-wide instance for the app delegate.
    public static let shared = FentonHingePresence()

    /// A hinge has been observed on this device.
    public private(set) var hasHinge = false

    /// Called once, the first time a hinge is recorded.
    public var onFirstHinge: @MainActor () -> Void

    /// Creates a presence record.
    /// - Parameter onFirstHinge: Called once, the first time a hinge is recorded.
    public init(onFirstHinge: @escaping @MainActor () -> Void = {}) {
        self.onFirstHinge = onFirstHinge
    }

    /// Records the latest observations.
    /// - Parameters:
    ///   - hinge: The latest hinge value; nil on devices without a hinge.
    ///   - hasVerticalBar: The system vertical bar is in use (only a folding phone has one).
    public func record(hinge: FentonHingeState?, hasVerticalBar: Bool = false) {
        guard hinge != nil || hasVerticalBar, !hasHinge else { return }
        hasHinge = true
        onFirstHinge()
    }

    /// Forgets that a hinge was seen. Tests only: the app never clears it.
    public func resetForTests() {
        hasHinge = false
    }
}
