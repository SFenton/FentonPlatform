import CoreGraphics
import XCTest
@testable import FentonAppleCore

/// Hinge avoidance geometry on the measured unfolded Duo: 868 pt of content, hinge band 455.3 to 495.7.
final class FentonHingeAvoidanceTests: XCTestCase {
    private let hinge = CGRect(x: 455.3, y: 0, width: 40.4, height: 669)
    private let content = CGRect(x: 0, y: 0, width: 868, height: 669)

    func testAVerticalHingeAcrossTheContainerIsABandInLocalOffsets() throws {
        let band = try XCTUnwrap(FentonHingeAvoidance.band(in: content, hinge: hinge))
        XCTAssertEqual(band.lowerBound, 455.3, accuracy: 0.001)
        XCTAssertEqual(band.upperBound, 495.7, accuracy: 0.001)
        let shifted = try XCTUnwrap(FentonHingeAvoidance.band(in: CGRect(x: 100, y: 0, width: 700, height: 600), hinge: hinge))
        XCTAssertEqual(shifted.lowerBound, 355.3, accuracy: 0.001)
    }

    func testNoBandWithoutAVerticalHingeInsideTheContainer() {
        XCTAssertNil(FentonHingeAvoidance.band(in: content, hinge: nil))
        XCTAssertNil(FentonHingeAvoidance.band(in: content, hinge: CGRect(x: 0, y: 455.3, width: 951, height: 40.4)))
        XCTAssertNil(FentonHingeAvoidance.band(in: CGRect(x: 500, y: 0, width: 368, height: 669), hinge: hinge))
        XCTAssertNil(FentonHingeAvoidance.band(in: content, hinge: .zero))
    }

    func testABandClipsToTheContainer() throws {
        let band = try XCTUnwrap(FentonHingeAvoidance.band(in: CGRect(x: 470, y: 0, width: 300, height: 100), hinge: hinge))
        XCTAssertEqual(band.lowerBound, 0)
    }

    func testAnObjectStaysCentredWhenTheBandMissesIt() {
        let clear = FentonHingeAvoidance.placement(objectWidth: 868, containerWidth: 868, band: nil)
        XCTAssertEqual(clear.x, 0)
        XCTAssertEqual(clear.width, 868)
        let beside = FentonHingeAvoidance.placement(objectWidth: 300, containerWidth: 868, band: 700...740)
        XCTAssertEqual(beside.x, 284)
        XCTAssertEqual(beside.width, 300)
        let oversize = FentonHingeAvoidance.placement(objectWidth: 2000, containerWidth: 868, band: nil)
        XCTAssertEqual(oversize.width, 868)
    }

    func testAnObjectTheBandCrossesMovesToTheLeadingRegionsCentre() {
        let band: ClosedRange<CGFloat> = 455.3...495.7
        let alarm = FentonHingeAvoidance.placement(objectWidth: 560, containerWidth: 868, band: band)
        XCTAssertEqual(alarm.width, 455.3, accuracy: 0.001)
        XCTAssertEqual(alarm.x, 0, accuracy: 0.001)
        let form = FentonHingeAvoidance.placement(objectWidth: 300, containerWidth: 868, band: band)
        XCTAssertEqual(form.width, 300)
        XCTAssertEqual(form.x, 77.65, accuracy: 0.001)
    }

    func testAClearRegionIsTheWiderSideOfTheBand() {
        let band: ClosedRange<CGFloat> = 455.3...495.7
        let leading = FentonHingeAvoidance.clearRegion(containerWidth: 868, band: band)
        XCTAssertEqual(leading.x, 0)
        XCTAssertEqual(leading.width, 455.3, accuracy: 0.001)
        // The trailing side is wider.
        let trailing = FentonHingeAvoidance.clearRegion(containerWidth: 540, band: 100...140)
        XCTAssertEqual(trailing.x, 140)
        XCTAssertEqual(trailing.width, 400)
        let whole = FentonHingeAvoidance.clearRegion(containerWidth: 540, band: nil)
        XCTAssertEqual(whole.x, 0)
        XCTAssertEqual(whole.width, 540)
        XCTAssertEqual(FentonHingeAvoidance.clearRegion(containerWidth: 200, band: 100...100).x, 0)
    }
}
