import CoreGraphics
import XCTest
@testable import FentonAppleCore

/// The split rule table of the shared split-view design, on measured window sizes.
final class FentonSplitPolicyTests: XCTestCase {
    private let policy = FentonSplitPolicy()
    private let iPhonePortrait = CGSize(width: 402, height: 874)
    private let duoOuter = CGSize(width: 466, height: 678)
    private let duoOuterLandscape = CGSize(width: 678, height: 466)
    private let duoInnerLandscape = CGSize(width: 951, height: 669)
    private let duoInnerPortrait = CGSize(width: 669, height: 951)
    private let iPadPortrait = CGSize(width: 834, height: 1210)
    private let iPadLandscape = CGSize(width: 1210, height: 834)
    private let hinge = CGRect(x: 455.3, y: 0, width: 40.4, height: 669)
    private let duoContent = CGRect(x: 0, y: 0, width: 868, height: 669)

    func testDefaults() {
        XCTAssertEqual(policy.minimumPaneWidth, 360)
        XCTAssertEqual(policy.midpointBandWidth, 1)
    }

    func testSplitsOnlyInRegularLandscape() {
        XCTAssertFalse(policy.allowsSplit(size: iPhonePortrait, isRegularWidth: false))
        XCTAssertFalse(policy.allowsSplit(size: duoOuter, isRegularWidth: false))
        XCTAssertFalse(policy.allowsSplit(size: duoOuterLandscape, isRegularWidth: false))
        XCTAssertFalse(policy.allowsSplit(size: duoInnerPortrait, isRegularWidth: true))
        XCTAssertFalse(policy.allowsSplit(size: iPadPortrait, isRegularWidth: true))
        XCTAssertTrue(policy.allowsSplit(size: duoInnerLandscape, isRegularWidth: true))
        XCTAssertTrue(policy.allowsSplit(size: iPadLandscape, isRegularWidth: true))
    }

    func testNarrowLandscapeWindowsDoNotSplit() {
        XCTAssertFalse(policy.allowsSplit(size: CGSize(width: 700, height: 500), isRegularWidth: true))
    }

    func testDividerFollowsHingeElseMidpoint() {
        XCTAssertEqual(policy.dividerX(width: 951, hingeMidX: 470), 470)
        XCTAssertEqual(policy.dividerX(width: 1210, hingeMidX: nil), 605)
        XCTAssertEqual(policy.dividerX(width: 1210, hingeMidX: 2000), 605)
        XCTAssertEqual(policy.dividerX(width: 1210, hingeMidX: 0), 605)
    }

    func testPartlyFoldedLandscapeSplitsOnTheHinge() throws {
        let geometry = try XCTUnwrap(policy.geometry(container: duoContent, isRegularWidth: true, hinge: hinge))
        XCTAssertTrue(geometry.isHinge)
        XCTAssertEqual(geometry.leadingWidth, 455.3, accuracy: 0.001)
        XCTAssertEqual(geometry.bandWidth, 40.4, accuracy: 0.001)
        XCTAssertEqual(geometry.trailingWidth, 372.3, accuracy: 0.001)
    }

    func testFlatDuoDividesAtTheMidpointWithTheThinBand() throws {
        let geometry = try XCTUnwrap(policy.geometry(container: duoContent, isRegularWidth: true, hinge: nil))
        XCTAssertFalse(geometry.isHinge)
        XCTAssertEqual(geometry.leadingWidth, 433.5, accuracy: 0.001)
        XCTAssertEqual(geometry.bandWidth, 1, accuracy: 0.001)
        XCTAssertEqual(geometry.trailingWidth, 433.5, accuracy: 0.001)
    }

    func testAHorizontalHingeIsIgnoredForTheSplit() throws {
        let horizontal = CGRect(x: 0, y: 300, width: 868, height: 40)
        let geometry = try XCTUnwrap(policy.geometry(container: duoContent, isRegularWidth: true, hinge: horizontal))
        XCTAssertFalse(geometry.isHinge)
    }

    func testAWiderZeroWidthHingeIsWidenedToTheMidpointBand() throws {
        let slit = CGRect(x: 434, y: 0, width: 0, height: 669)
        let geometry = try XCTUnwrap(policy.geometry(container: duoContent, isRegularWidth: true, hinge: slit))
        XCTAssertTrue(geometry.isHinge)
        XCTAssertEqual(geometry.bandWidth, 1, accuracy: 0.001)
    }

    func testEachHalfUnderTheMinimumReturnsNil() {
        // Leading half under 360: the hinge sits left of the window's middle.
        let early = CGRect(x: 300, y: 0, width: 40, height: 669)
        XCTAssertNil(policy.geometry(container: duoContent, isRegularWidth: true, hinge: early))
        // Trailing half under 360.
        let late = CGRect(x: 520, y: 0, width: 40, height: 669)
        XCTAssertNil(policy.geometry(container: duoContent, isRegularWidth: true, hinge: late))
        // A window that does not split at all.
        XCTAssertNil(policy.geometry(container: CGRect(x: 0, y: 0, width: 600, height: 700), isRegularWidth: true, hinge: nil))
    }

    func testCustomMinimumAndBand() throws {
        let custom = FentonSplitPolicy(minimumPaneWidth: 200, midpointBandWidth: 8)
        let geometry = try XCTUnwrap(custom.geometry(container: CGRect(x: 0, y: 0, width: 500, height: 400), isRegularWidth: true, hinge: nil))
        XCTAssertEqual(geometry.bandWidth, 8, accuracy: 0.001)
        XCTAssertEqual(geometry.leadingWidth, 246, accuracy: 0.001)
    }

    func testColumnWidthsPutTheHingeBetweenThePanes() {
        let geometry = policy.columnWidths(container: duoContent, hinge: hinge, gutter: 24)
        XCTAssertTrue(geometry.isHinge)
        XCTAssertEqual(geometry.leadingWidth, 455.3, accuracy: 0.001)
        XCTAssertEqual(geometry.bandWidth, 40.4, accuracy: 0.001)
        XCTAssertEqual(geometry.trailingWidth, 372.3, accuracy: 0.001)
        XCTAssertEqual(geometry.leadingWidth + geometry.bandWidth + geometry.trailingWidth, 868, accuracy: 0.001)
    }

    func testColumnWidthsFallBackToTheGutterWithoutAUsableHinge() {
        let ipad = policy.columnWidths(container: CGRect(x: 0, y: 0, width: 1194, height: 834), hinge: nil, gutter: 24)
        XCTAssertFalse(ipad.isHinge)
        XCTAssertEqual(ipad.leadingWidth, 585)
        XCTAssertEqual(ipad.trailingWidth, 585)
        XCTAssertEqual(ipad.bandWidth, 24)
        // The pane after the hinge would be 300 pt, under the 360 minimum.
        let narrow = policy.columnWidths(container: CGRect(x: 0, y: 0, width: 796, height: 669), hinge: hinge, gutter: 12)
        XCTAssertFalse(narrow.isHinge)
        // A leading pane under the minimum.
        let early = policy.columnWidths(container: duoContent, hinge: CGRect(x: 300, y: 0, width: 40, height: 669), gutter: 12)
        XCTAssertFalse(early.isHinge)
    }

    func testColumnWidthsNeverGoNegative() {
        let horizontal = CGRect(x: 0, y: 455.3, width: 951, height: 40.4)
        XCTAssertFalse(policy.columnWidths(container: duoContent, hinge: horizontal, gutter: 24).isHinge)
        let none = policy.columnWidths(container: .zero, hinge: hinge, gutter: 24)
        XCTAssertEqual(none.leadingWidth, 0)
        XCTAssertEqual(none.trailingWidth, 0)
        XCTAssertEqual(policy.columnWidths(container: duoContent, hinge: nil, gutter: -5).bandWidth, 0)
    }
}
