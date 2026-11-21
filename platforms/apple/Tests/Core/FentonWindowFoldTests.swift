import CoreGraphics
import XCTest
@testable import FentonAppleCore

final class FentonWindowFoldTests: XCTestCase {
    private let vertical = CGRect(x: 455.3, y: 0, width: 40.4, height: 669)

    func testFoldingIsForcedOffWithoutAHinge() {
        XCTAssertFalse(FentonWindowFold(hinge: nil, isFolding: true).isFolding)
        XCTAssertEqual(FentonWindowFold.none, FentonWindowFold(hinge: nil, isFolding: true))
    }

    func testBandIsTheHingeOnlyWhileFolding() {
        XCTAssertEqual(FentonWindowFold(hinge: vertical, isFolding: true).band, vertical)
        XCTAssertNil(FentonWindowFold(hinge: vertical, isFolding: false).band)
        XCTAssertNil(FentonWindowFold.none.band)
    }

    func testVerticalMeansTallerThanWide() {
        XCTAssertTrue(FentonWindowFold(hinge: vertical, isFolding: false).isVertical)
        XCTAssertFalse(FentonWindowFold(hinge: CGRect(x: 0, y: 455, width: 951, height: 40), isFolding: true).isVertical)
        XCTAssertFalse(FentonWindowFold.none.isVertical)
    }

    func testClearingTheHingeClearsFolding() {
        var fold = FentonWindowFold(hinge: vertical, isFolding: true)
        fold.hinge = nil
        XCTAssertFalse(fold.isFolding)
        var flat = FentonWindowFold.none
        flat.isFolding = true
        XCTAssertFalse(flat.isFolding)
        flat.hinge = vertical
        flat.isFolding = true
        XCTAssertTrue(flat.isFolding)
    }
}
