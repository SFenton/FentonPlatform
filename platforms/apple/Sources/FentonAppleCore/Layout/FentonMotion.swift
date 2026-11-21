import Foundation

/// Mechanism only: the app supplies the numbers. Every field defaults to today's shipped value.
public struct FentonMotion: Sendable, Equatable {
    /// A spring's two numbers.
    public struct Spring: Sendable, Equatable {
        /// The spring's duration in seconds.
        public var duration: TimeInterval
        /// The spring's bounce; 0 does not overshoot.
        public var bounce: Double

        /// Creates a spring.
        public init(duration: TimeInterval, bounce: Double) {
            self.duration = duration
            self.bounce = bounce
        }
    }

    /// The standard spring for a layout change.
    public var standard: Spring
    /// The short duration used in place of ``standard`` under Reduce Motion.
    public var quick: TimeInterval
    /// The cross-fade duration.
    public var crossFade: TimeInterval

    /// Creates a motion set.
    public init(standard: Spring = .init(duration: 0.3, bounce: 0), quick: TimeInterval = 0.2, crossFade: TimeInterval = 0.2) {
        self.standard = standard
        self.quick = quick
        self.crossFade = crossFade
    }
}
