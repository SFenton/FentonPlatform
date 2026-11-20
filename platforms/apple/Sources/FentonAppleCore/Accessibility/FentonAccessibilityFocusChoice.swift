import CoreGraphics

/// Pure choice of the element an assistive-technology focus move lands on, so the rule is unit-tested without UIKit: the
/// top-most heading (then leading-most) whose centre lies inside the region.
public enum FentonAccessibilityFocusChoice {
    /// A candidate element as the walker read it.
    public struct Candidate: Equatable, Sendable {
        /// The element's accessibility label.
        public let label: String
        /// The element's accessibility identifier.
        public let identifier: String
        /// The element's frame, in the same space as the region.
        public let frame: CGRect
        /// The element has the header trait.
        public let isHeading: Bool

        /// Creates a candidate.
        public init(label: String, identifier: String, frame: CGRect, isHeading: Bool) {
            self.label = label
            self.identifier = identifier
            self.frame = frame
            self.isHeading = isHeading
        }
    }

    /// The candidate a "top heading" request lands on.
    /// - Parameters:
    ///   - candidates: Elements of the window, in any order.
    ///   - region: The anchor's frame (screen coordinates).
    /// - Returns: The index of the top-most, then leading-most, heading whose centre lies in `region` (a named heading of zero
    ///   size never counts), or nil.
    public static func topHeading(_ candidates: [Candidate], in region: CGRect) -> Int? {
        candidates.indices
            .filter { index in
                let item = candidates[index]
                return item.isHeading && !item.label.isEmpty && item.frame.width > 0 && item.frame.height > 0
                    && region.contains(CGPoint(x: item.frame.midX, y: item.frame.midY))
            }
            .min { lhs, rhs in
                let a = candidates[lhs].frame, b = candidates[rhs].frame
                return abs(a.minY - b.minY) > 1 ? a.minY < b.minY : a.minX < b.minX
            }
    }
}
