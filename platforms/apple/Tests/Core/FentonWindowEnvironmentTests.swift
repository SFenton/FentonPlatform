import CoreGraphics
import XCTest
@testable import FentonAppleCore

@MainActor
final class FentonWindowEnvironmentTests: XCTestCase {
    func testDefaultsAreQuiet() {
        let environment = FentonWindowEnvironment()
        XCTAssertEqual(environment.fold, .none)
        XCTAssertNil(environment.band)
        XCTAssertFalse(environment.inVerticalBar)
        XCTAssertFalse(environment.reduceMotion)
        XCTAssertFalse(environment.reduceTransparency)
        XCTAssertNil(environment.headerEdgeCap)
    }

    func testBandFollowsTheFold() {
        let environment = FentonWindowEnvironment()
        let hinge = CGRect(x: 455, y: 0, width: 40, height: 669)
        environment.fold = FentonWindowFold(hinge: hinge, isFolding: true)
        XCTAssertEqual(environment.band, hinge)
        environment.fold = FentonWindowFold(hinge: hinge, isFolding: false)
        XCTAssertNil(environment.band)
    }

    func testBindingsHearOnlyTheFieldsTheyRead() {
        let environment = FentonWindowEnvironment()
        var foldReads = 0
        let observation = FentonObservation {
            _ = environment.fold
            foldReads += 1
        }
        environment.reduceMotion = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(foldReads, 1)
        environment.fold = FentonWindowFold(hinge: CGRect(x: 1, y: 0, width: 2, height: 3), isFolding: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(foldReads, 2)
        observation.cancel()
    }

    func testMotionDefaults() {
        let motion = FentonMotion()
        XCTAssertEqual(motion.standard, FentonMotion.Spring(duration: 0.3, bounce: 0))
        XCTAssertEqual(motion.quick, 0.2)
        XCTAssertEqual(motion.crossFade, 0.2)
        let custom = FentonMotion(standard: .init(duration: 0.5, bounce: 0.1), quick: 0.1, crossFade: 0.4)
        XCTAssertNotEqual(custom, motion)
    }
}
