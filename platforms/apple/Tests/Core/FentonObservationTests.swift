import Foundation
import Observation
import XCTest
@testable import FentonAppleCore

@MainActor
final class FentonObservationTests: XCTestCase {
    @Observable
    final class Model {
        var value = 0
        var other = 0
    }

    private func turn() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }

    func testApplyRunsNowAndOncePerTurnAfterChanges() {
        let model = Model()
        var applications = 0
        let observation = FentonObservation {
            _ = model.value
            applications += 1
        }
        XCTAssertEqual(applications, 1)
        model.value = 1
        model.value = 2
        turn()
        XCTAssertEqual(applications, 2)
        observation.cancel()
        model.value = 3
        turn()
        XCTAssertEqual(applications, 2)
    }

    func testTrackApplyDoesNotRetrackWhatApplyReads() {
        let model = Model()
        var applications = 0
        let observation = FentonObservation(track: { _ = model.value }, apply: {
            _ = model.other
            applications += 1
        })
        XCTAssertEqual(applications, 1)
        model.other = 5
        turn()
        XCTAssertEqual(applications, 1, "apply's own reads are not tracked")
        model.value = 1
        turn()
        XCTAssertEqual(applications, 2)
        observation.cancel()
    }

    func testPauseRunsOneCatchUpOnResume() {
        let model = Model()
        var applications = 0
        let observation = FentonObservation {
            _ = model.value
            applications += 1
        }
        XCTAssertFalse(observation.resume(), "not paused")
        observation.pause()
        model.value = 1
        turn()
        model.value = 2
        turn()
        XCTAssertEqual(applications, 1)
        XCTAssertTrue(observation.resume())
        XCTAssertEqual(applications, 2)
        XCTAssertFalse(observation.resume())
        model.value = 3
        turn()
        XCTAssertEqual(applications, 3)
        observation.cancel()
    }

    func testResumeWithoutAChangeDoesNotRunAndCancelledDoesNotCatchUp() {
        let model = Model()
        var applications = 0
        let quiet = FentonObservation { _ = model.value; applications += 1 }
        quiet.pause()
        XCTAssertFalse(quiet.resume())
        XCTAssertEqual(applications, 1)

        quiet.pause()
        model.value = 1
        turn()
        quiet.cancel()
        XCTAssertFalse(quiet.resume())
        XCTAssertEqual(applications, 1)
    }

    func testAChangeHeardWhilePausedIsHeldNotQueued() {
        let model = Model()
        var applications = 0
        let observation = FentonObservation { _ = model.value; applications += 1 }
        model.value = 1
        observation.pause()
        turn()
        XCTAssertEqual(applications, 1)
        XCTAssertTrue(observation.resume())
        XCTAssertEqual(applications, 2)
        observation.cancel()
    }

    func testBagCancellationStopsFurtherUpdates() {
        let model = Model()
        var applications = 0
        let bag = FentonObservationBag()
        bag.observe {
            _ = model.value
            applications += 1
        }
        XCTAssertEqual(applications, 1)
        bag.removeAll()
        model.value = 1
        turn()
        XCTAssertEqual(applications, 1)
    }

    func testDroppingBagEndsObservationLifetime() {
        let model = Model()
        var applications = 0
        var bag: FentonObservationBag? = FentonObservationBag()
        bag?.observe {
            _ = model.value
            applications += 1
        }
        bag = nil
        model.value = 1
        turn()
        XCTAssertEqual(applications, 1)
    }

    func testBagTrackApplyAndPauseResume() {
        let model = Model()
        var plain = 0
        var split = 0
        let bag = FentonObservationBag()
        bag.observe { _ = model.value; plain += 1 }
        bag.observe(track: { _ = model.value }, apply: { split += 1 })
        XCTAssertFalse(bag.isPaused)
        bag.pause()
        XCTAssertTrue(bag.isPaused)
        // An observation made while paused still draws once.
        var late = 0
        bag.observe { _ = model.other; late += 1 }
        XCTAssertEqual(late, 1)
        model.value = 1
        model.other = 1
        turn()
        XCTAssertEqual([plain, split, late], [1, 1, 1])
        XCTAssertEqual(bag.resume(), 3)
        XCTAssertEqual([plain, split, late], [2, 2, 2])
        XCTAssertFalse(bag.isPaused)
        XCTAssertEqual(bag.resume(), 0)
    }

    func testOwnerOverloadDoesNotRetainOwner() {
        final class Owner {
            var applications = 0
        }
        let model = Model()
        var owner: Owner? = Owner()
        weak let weakOwner = owner
        let bag = FentonObservationBag()
        if let owner {
            bag.observe(owner: owner) { owner in
                _ = model.value
                owner.applications += 1
            }
            XCTAssertEqual(owner.applications, 1)
        }
        owner = nil
        XCTAssertNil(weakOwner)
        model.value = 1
        turn()
        XCTAssertNil(weakOwner)
    }
}
