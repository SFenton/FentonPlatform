import CoreGraphics
import XCTest
@testable import FentonAppleCore

final class FentonAccessibilityFocusChoiceTests: XCTestCase {
    private typealias Candidate = FentonAccessibilityFocusChoice.Candidate
    private let region = CGRect(x: 0, y: 0, width: 400, height: 800)

    private func heading(_ label: String, x: CGFloat, y: CGFloat, w: CGFloat = 100, h: CGFloat = 30, isHeading: Bool = true) -> Candidate {
        Candidate(label: label, identifier: "id.\(label)", frame: CGRect(x: x, y: y, width: w, height: h), isHeading: isHeading)
    }

    func testTheTopMostHeadingWins() {
        let items = [heading("lower", x: 10, y: 200), heading("upper", x: 200, y: 20), heading("middle", x: 10, y: 100)]
        XCTAssertEqual(FentonAccessibilityFocusChoice.topHeading(items, in: region), 1)
    }

    func testOnTheSameLineTheLeadingMostWins() {
        let items = [heading("right", x: 200, y: 20.5), heading("left", x: 10, y: 20)]
        XCTAssertEqual(FentonAccessibilityFocusChoice.topHeading(items, in: region), 1)
    }

    func testZeroSizeUnlabeledNonHeadingAndOutsideAreIgnored() {
        let items = [
            heading("zero", x: 10, y: 0, w: 0, h: 0),
            heading("", x: 10, y: 1),
            heading("plain", x: 10, y: 2, isHeading: false),
            heading("outside", x: 900, y: 3),
            heading("kept", x: 10, y: 300)
        ]
        XCTAssertEqual(FentonAccessibilityFocusChoice.topHeading(items, in: region), 4)
        XCTAssertNil(FentonAccessibilityFocusChoice.topHeading(Array(items.dropLast()), in: region))
        XCTAssertNil(FentonAccessibilityFocusChoice.topHeading([], in: region))
    }
}
