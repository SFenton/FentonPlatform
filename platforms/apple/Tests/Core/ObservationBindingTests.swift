import Foundation
import Observation
import XCTest
@testable import FentonAppleCore

@MainActor
final class ObservationBindingTests: XCTestCase {
    @Observable
    final class Model {
        var value = 0
    }

    func testChangesAreCoalescedOnTheNextMainRunLoopTurn() {
        let model = Model()
        var applications = 0
        let binding = ObservationBinding {
            _ = model.value
            applications += 1
        }

        model.value = 1
        model.value = 2
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(applications, 2)
        binding.cancel()
    }

    func testBagCancellationStopsFurtherUpdates() {
        let model = Model()
        var applications = 0
        let bag = ObservationBag()
        bag.observe {
            _ = model.value
            applications += 1
        }
        XCTAssertEqual(applications, 1)

        bag.removeAll()
        model.value = 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(applications, 1)
    }

    func testDroppingBagEndsObservationLifetime() {
        let model = Model()
        var applications = 0
        var bag: ObservationBag? = ObservationBag()
        bag?.observe {
            _ = model.value
            applications += 1
        }
        XCTAssertEqual(applications, 1)

        bag = nil
        model.value = 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(applications, 1)
    }

    func testOwnerOverloadDoesNotRetainOwner() {
        final class Owner {
            var applications = 0
        }

        let model = Model()
        var owner: Owner? = Owner()
        let bag = ObservationBag()
        weak var weakOwner = owner
        bag.observe(owner: owner!) { owner in
            _ = model.value
            owner.applications += 1
        }
        XCTAssertEqual(owner?.applications, 1)

        owner = nil
        XCTAssertNil(weakOwner)
        model.value = 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertNil(weakOwner)
    }
}
