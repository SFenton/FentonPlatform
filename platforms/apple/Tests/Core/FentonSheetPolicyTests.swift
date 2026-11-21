import CoreGraphics
import XCTest
@testable import FentonAppleCore

final class FentonSheetPolicyTests: XCTestCase {
    private let vertical = CGRect(x: 455.3, y: 0, width: 40.4, height: 669)

    func testFillsHeightFollowsTheHingeGeometry() {
        XCTAssertFalse(FentonSheetPolicy.fillsHeight(hasHinge: false, hinge: nil))
        XCTAssertFalse(FentonSheetPolicy.fillsHeight(hasHinge: false, hinge: vertical))
        XCTAssertTrue(FentonSheetPolicy.fillsHeight(hasHinge: true, hinge: nil), "folded outer screen")
        XCTAssertTrue(FentonSheetPolicy.fillsHeight(hasHinge: true, hinge: vertical))
        XCTAssertFalse(FentonSheetPolicy.fillsHeight(hasHinge: true, hinge: CGRect(x: 0, y: 455, width: 951, height: 40)))
    }

    func testLeadingHalfEndsAtTheHingeWhileFolding() {
        let fold = FentonWindowFold(hinge: vertical, isFolding: true)
        XCTAssertEqual(FentonSheetPolicy.leadingHalfWidth(fold: fold, freeWidth: 868), 447)
    }

    func testLeadingHalfEndsAtTheMidpointWhileFlat() {
        let fold = FentonWindowFold(hinge: vertical, isFolding: false)
        // (868 - 1) / 2 = 433.5; less the 8 pt margin, rounded down.
        XCTAssertEqual(FentonSheetPolicy.leadingHalfWidth(fold: fold, freeWidth: 868), 425)
    }

    func testNoLeadingHalfWithoutAVerticalHinge() {
        XCTAssertNil(FentonSheetPolicy.leadingHalfWidth(fold: .none, freeWidth: 868))
        let horizontal = FentonWindowFold(hinge: CGRect(x: 0, y: 455, width: 951, height: 40), isFolding: true)
        XCTAssertNil(FentonSheetPolicy.leadingHalfWidth(fold: horizontal, freeWidth: 951))
    }

    func testLeadingHalfIsNeverNegative() {
        let fold = FentonWindowFold(hinge: CGRect(x: 2, y: 0, width: 4, height: 100), isFolding: true)
        XCTAssertEqual(FentonSheetPolicy.leadingHalfWidth(fold: fold, freeWidth: 10), 0)
        XCTAssertEqual(FentonSheetPolicy.leadingHalfWidth(fold: FentonWindowFold(hinge: vertical, isFolding: false), freeWidth: 0), 0)
    }

    func testConstants() {
        XCTAssertEqual(FentonSheetPolicy.halfMargin, 8)
        XCTAssertEqual(FentonSheetPolicy.midpointBand, 1)
        XCTAssertEqual(FentonSheetPolicy.midpointBand, FentonSplitPolicy().midpointBandWidth)
    }

    func testSheetHeightPolicyCases() {
        XCTAssertNotEqual(FentonSheetHeightPolicy.medium, .large)
        XCTAssertEqual(FentonSheetHeightPolicy.mediumAndLarge, .mediumAndLarge)
    }
}
