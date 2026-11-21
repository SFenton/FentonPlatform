import CoreGraphics
import XCTest
@testable import FentonAppleCore

final class FentonScrollEdgeFadeTests: XCTestCase {
    func testHeaderIsTheLargerReadingNeverTheirSum() {
        XCTAssertEqual(FentonScrollEdgeFade.headerHeight(safeAreaInset: 96, containerOffset: 0), 96)
        XCTAssertEqual(FentonScrollEdgeFade.headerHeight(safeAreaInset: 56, containerOffset: 56), 56)
        XCTAssertEqual(FentonScrollEdgeFade.headerHeight(safeAreaInset: 0, containerOffset: 120), 120)
        XCTAssertEqual(FentonScrollEdgeFade.headerHeight(safeAreaInset: -4, containerOffset: -8), 0)
        XCTAssertEqual(FentonScrollEdgeFade.headerHeight(safeAreaInset: .nan, containerOffset: 30), 30)
        XCTAssertEqual(FentonScrollEdgeFade.headerHeight(safeAreaInset: .infinity, containerOffset: .nan), 0)
    }

    func testTheCapIsTheStatusRegionAloneWhenTheBarIsATrailingRail() {
        XCTAssertEqual(FentonScrollEdgeFade.edgeCap(statusTop: 62, barHeight: 44, barIsRail: false), 106)
        XCTAssertEqual(FentonScrollEdgeFade.edgeCap(statusTop: 62, barHeight: 44, barIsRail: true), 62)
        XCTAssertNil(FentonScrollEdgeFade.edgeCap(statusTop: 0, barHeight: 44, barIsRail: false))
    }

    func testClearBandStopsAtTheInlineBarSoLargeTitlesShow() {
        XCTAssertEqual(FentonScrollEdgeFade.clearHeight(header: 170, smallestInset: 170, cap: 106), 106)
        XCTAssertEqual(FentonScrollEdgeFade.clearHeight(header: 170, smallestInset: 104, cap: 110), 104)
        XCTAssertEqual(FentonScrollEdgeFade.clearHeight(header: 56, smallestInset: 56, cap: 106), 56)
        XCTAssertEqual(FentonScrollEdgeFade.clearHeight(header: 80, smallestInset: nil, cap: nil), 80)
        XCTAssertEqual(FentonScrollEdgeFade.clearHeight(header: 80, smallestInset: .nan, cap: -1), 80)
    }

    func testFadeGrowsLinearlyOverTheFirstFortyPoints() {
        XCTAssertEqual(FentonScrollEdgeFade.rampHeight, 40)
        XCTAssertEqual(FentonScrollEdgeFade.progress(scrollOffset: 0), 0)
        XCTAssertEqual(FentonScrollEdgeFade.progress(scrollOffset: -30), 0)
        XCTAssertEqual(FentonScrollEdgeFade.progress(scrollOffset: 10), 0.25)
        XCTAssertEqual(FentonScrollEdgeFade.progress(scrollOffset: 40), 1)
        XCTAssertEqual(FentonScrollEdgeFade.progress(scrollOffset: 400), 1)
        XCTAssertEqual(FentonScrollEdgeFade.progress(scrollOffset: .nan), 0)
    }

    func testHardEdgeIsClearAsSoonAsContentScrolls() {
        XCTAssertEqual(FentonScrollEdgeFade.progress(scrollOffset: 0, rampHeight: 0), 0)
        XCTAssertEqual(FentonScrollEdgeFade.progress(scrollOffset: 1, rampHeight: 0), 1)
    }

    func testEdgeIsOpaqueAtRestAndClearOnceScrolled() {
        XCTAssertEqual(FentonScrollEdgeFade.edgeOpacity(progress: 0), 1)
        XCTAssertEqual(FentonScrollEdgeFade.edgeOpacity(progress: 0.25), 0.75)
        XCTAssertEqual(FentonScrollEdgeFade.edgeOpacity(progress: 1), 0)
        XCTAssertEqual(FentonScrollEdgeFade.edgeOpacity(progress: 3), 0)
        XCTAssertEqual(FentonScrollEdgeFade.edgeOpacity(progress: .nan), 1)
    }

    func testTrackedOffsetIsWholePointsClampedToTheRamp() {
        XCTAssertEqual(FentonScrollEdgeFade.trackedOffset(contentOffset: -100, topInset: 100), 0)
        XCTAssertEqual(FentonScrollEdgeFade.trackedOffset(contentOffset: -160, topInset: 100), -1)
        XCTAssertEqual(FentonScrollEdgeFade.trackedOffset(contentOffset: -80.4, topInset: 100), 20)
        XCTAssertEqual(FentonScrollEdgeFade.trackedOffset(contentOffset: 500, topInset: 100), 41)
        XCTAssertEqual(FentonScrollEdgeFade.trackedOffset(contentOffset: 500, topInset: 0, rampHeight: 10), 11)
    }

    func testAccessibilitySettingsAndMissingScrollTrackingGiveAHardEdge() {
        XCTAssertEqual(FentonScrollEdgeFade.ramp(reduceTransparency: false, increaseContrast: false, tracksScroll: true), 40)
        XCTAssertEqual(FentonScrollEdgeFade.ramp(reduceTransparency: true, increaseContrast: false, tracksScroll: true), 0)
        XCTAssertEqual(FentonScrollEdgeFade.ramp(reduceTransparency: false, increaseContrast: true, tracksScroll: true), 0)
        XCTAssertEqual(FentonScrollEdgeFade.ramp(reduceTransparency: false, increaseContrast: false, tracksScroll: false), 0)
        XCTAssertEqual(FentonScrollEdgeFade.ramp(reduceTransparency: false, increaseContrast: false, tracksScroll: true, base: 24), 24)
    }
}
