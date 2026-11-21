#if os(iOS)
import FentonAppleCore
@testable import FentonUIKit
import UIKit
import XCTest

// MARK: - Support shared by the lane B hosted tests

/// A window in the host app's scene, run-loop spinning, and a stand-in for the hinge hardware.
@MainActor
enum LaneBHost {
    /// A visible window (not key) in the host app's scene that shows `root`.
    static func window(showing root: UIViewController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.isHidden = false
        window.layoutIfNeeded()
        return window
    }

    /// Lets the main run loop turn for `seconds`.
    static func spin(_ seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Turns the run loop until `condition` holds or `timeout` passes.
    @discardableResult
    static func spin(until condition: @MainActor () -> Bool, timeout: TimeInterval = 3) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { spin(0.02) }
        return condition()
    }
}

/// A folding phone in any pose: the test sets the hinge and the bar, and ``sensors`` answers like the hardware would.
@MainActor
final class FakeDuo {
    var hinge: CGRect?
    var isActive = false
    var hasBar = false
    var reduceMotion = false
    var reduceTransparency = false

    var sensors: FentonWindowSensors {
        FentonWindowSensors(
            regions: { [self] _, includeInactive in
                guard let hinge else { return [] }
                if isActive { return [(frame: hinge, isActive: true)] }
                return includeInactive ? [(frame: hinge, isActive: false)] : []
            },
            hasVerticalBar: { [self] _ in hasBar },
            reduceMotion: { [self] in reduceMotion },
            reduceTransparency: { [self] in reduceTransparency }
        )
    }

    /// Partly folded in landscape: a vertical band down the middle of `size`.
    func partlyFolded(in size: CGSize) {
        hinge = CGRect(x: size.width / 2 - 1, y: 0, width: 2, height: size.height)
        isActive = true
    }

    /// Lying flat: the same band, reported inactive.
    func flat(in size: CGSize) {
        hinge = CGRect(x: size.width / 2 - 1, y: 0, width: 2, height: size.height)
        isActive = false
    }
}

// MARK: - Tests

@MainActor
final class WindowSignalsTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var presence = FentonHingePresence()

    override func setUp() async throws {
        try await super.setUp()
        presence = FentonHingePresence()
    }

    override func tearDown() async throws {
        windows.forEach { $0.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    /// A root controller in a window, with signals on a host view that fills it.
    private func makeSignals(_ duo: FakeDuo, reflow: FentonReflow? = FentonReflow()) throws -> (FentonWindowSignals, FentonWindowEnvironment, UIView, UIWindow) {
        let root = UIViewController()
        let window = try LaneBHost.window(showing: root)
        windows.append(window)
        let host = UIView(frame: root.view.bounds)
        host.backgroundColor = .systemBackground
        root.view.addSubview(host)
        // A snapshot needs a view that has been drawn once.
        LaneBHost.spin(0.1)
        let environment = FentonWindowEnvironment()
        let signals = FentonWindowSignals(view: host, environment: environment, presence: presence, sensors: duo.sensors, reflow: reflow)
        return (signals, environment, host, window)
    }

    // MARK: Fold, band, bar

    func testPartlyFoldedWritesFoldBandAndNoBar() throws {
        let duo = FakeDuo()
        let (signals, environment, host, _) = try makeSignals(duo)
        duo.partlyFolded(in: host.bounds.size)
        signals.refresh()
        XCTAssertEqual(environment.fold, FentonWindowFold(hinge: duo.hinge, isFolding: true))
        XCTAssertEqual(environment.band, duo.hinge)
        XCTAssertFalse(environment.inVerticalBar)
    }

    func testFlatHasHingeButNoBand() throws {
        let duo = FakeDuo()
        let (signals, environment, host, _) = try makeSignals(duo)
        duo.flat(in: host.bounds.size)
        signals.refresh()
        XCTAssertEqual(environment.fold.hinge, duo.hinge)
        XCTAssertFalse(environment.fold.isFolding)
        XCTAssertNil(environment.band, "a flat device avoids nothing")
    }

    func testFoldedOuterScreenHasNoHingeButAVerticalBarRecordsPresence() throws {
        let duo = FakeDuo()
        duo.hasBar = true
        let (signals, environment, _, _) = try makeSignals(duo)
        signals.refresh()
        XCTAssertEqual(environment.fold, .none)
        XCTAssertTrue(environment.inVerticalBar)
        XCTAssertTrue(presence.hasHinge, "the bar proves a folding phone")
    }

    func testReduceMotionAndTransparencyAreWritten() throws {
        let duo = FakeDuo()
        duo.reduceMotion = true
        duo.reduceTransparency = true
        let (signals, environment, _, _) = try makeSignals(duo)
        signals.refresh()
        XCTAssertTrue(environment.reduceMotion)
        XCTAssertTrue(environment.reduceTransparency)
    }

    // MARK: One write per change

    func testRefreshWritesOnceAndASecondRefreshAtTheSameStateWritesNothing() throws {
        let duo = FakeDuo()
        let (signals, environment, host, _) = try makeSignals(duo)
        var folds = 0
        var bars = 0
        let bag = FentonObservationBag()
        bag.observe { _ = environment.fold; folds += 1 }
        bag.observe { _ = environment.inVerticalBar; bars += 1 }
        XCTAssertEqual([folds, bars], [1, 1], "each observation runs once on start")

        duo.partlyFolded(in: host.bounds.size)
        duo.hasBar = true
        signals.refresh()
        LaneBHost.spin()
        XCTAssertEqual([folds, bars], [2, 2], "one run per change")

        signals.refresh()
        signals.refresh()
        LaneBHost.spin()
        XCTAssertEqual([folds, bars], [2, 2], "the same state writes nothing")

        duo.flat(in: host.bounds.size)
        signals.refresh()
        LaneBHost.spin()
        XCTAssertEqual([folds, bars], [3, 2], "only the field that changed is rewritten")
        bag.removeAll()
    }

    // MARK: Reflow

    func testPostureChangeAtUnchangedSizeLeavesASnapshotUnderReduceMotionThatIsRemoved() throws {
        let duo = FakeDuo()
        duo.reduceMotion = true
        let (signals, _, host, _) = try makeSignals(duo)
        duo.partlyFolded(in: host.bounds.size)
        signals.refresh()
        XCTAssertEqual(host.subviews.count, 0, "the first fold is not a posture change")

        duo.flat(in: host.bounds.size)
        signals.refresh()
        XCTAssertEqual(host.subviews.count, 1, "the old picture lies over the host for the cross-fade")
        XCTAssertFalse(host.subviews[0].isUserInteractionEnabled)
        XCTAssertTrue(host.subviews[0].accessibilityElementsHidden)

        XCTAssertTrue(LaneBHost.spin(until: { host.subviews.isEmpty }), "the snapshot is removed after the fade")
    }

    func testPostureChangeWithoutReduceMotionTakesNoSnapshot() throws {
        let duo = FakeDuo()
        let (signals, environment, host, _) = try makeSignals(duo)
        duo.partlyFolded(in: host.bounds.size)
        signals.refresh()
        duo.flat(in: host.bounds.size)
        signals.refresh()
        XCTAssertEqual(host.subviews.count, 0)
        XCTAssertFalse(environment.fold.isFolding)
        LaneBHost.spin(0.4)
    }

    func testAChangeOfSizeIsARotationNotAPostureAndIsNotReflowed() throws {
        let duo = FakeDuo()
        duo.reduceMotion = true
        let (signals, _, host, _) = try makeSignals(duo)
        duo.partlyFolded(in: host.bounds.size)
        signals.refresh()
        host.frame.size.width += 40
        duo.flat(in: host.bounds.size)
        signals.refresh()
        XCTAssertEqual(host.subviews.count, 0, "a rotation is the system's to animate")
    }

    func testNilReflowChangesTheFoldWithoutAnimation() throws {
        let duo = FakeDuo()
        duo.reduceMotion = true
        let (signals, environment, host, _) = try makeSignals(duo, reflow: nil)
        duo.partlyFolded(in: host.bounds.size)
        signals.refresh()
        duo.flat(in: host.bounds.size)
        signals.refresh()
        XCTAssertEqual(host.subviews.count, 0)
        XCTAssertFalse(environment.fold.isFolding)
    }

    // MARK: Presence

    func testHingeInteractionRecordsPresenceOnceAndRefreshesNextTurn() throws {
        var firstHinges = 0
        presence = FentonHingePresence(onFirstHinge: { firstHinges += 1 })
        let duo = FakeDuo()
        let (signals, environment, host, _) = try makeSignals(duo)
        signals.hingeChanged(.partiallyOpen)
        signals.hingeChanged(.fullyOpen)
        signals.hingeChanged(nil)
        XCTAssertTrue(presence.hasHinge)
        XCTAssertEqual(firstHinges, 1)

        duo.partlyFolded(in: host.bounds.size)
        signals.hingeChanged(.partiallyOpen)
        XCTAssertTrue(LaneBHost.spin(until: { environment.fold.isFolding }), "the fold is read again on the next turn")
    }

    // MARK: Queries

    func testFoldInASheetViewIsAskedOfTheRootViewAndConverted() throws {
        let duo = FakeDuo()
        let root = UIViewController()
        let window = try LaneBHost.window(showing: root)
        windows.append(window)
        let size = root.view.bounds.size
        duo.flat(in: size)
        // A view with its own origin: the answer is in its coordinates.
        let offset = UIView(frame: CGRect(x: 100, y: 0, width: size.width - 100, height: size.height))
        root.view.addSubview(offset)
        let fold = FentonWindowSignals.fold(in: offset, sensors: duo.sensors)
        XCTAssertEqual(fold.hinge?.minX ?? 0, (duo.hinge?.minX ?? 0) - 100, accuracy: 0.01)
        XCTAssertFalse(fold.isFolding)
        XCTAssertEqual(FentonWindowSignals.fold(in: UIView(), sensors: FakeDuo().sensors), .none)
    }

    func testFreeWidthTakesOffTheRailOnlyWithAVerticalBar() throws {
        let duo = FakeDuo()
        let window = try LaneBHost.window(showing: UIViewController())
        windows.append(window)
        XCTAssertEqual(FentonWindowSignals.railWidth(in: window, sensors: duo.sensors), 0)
        XCTAssertEqual(FentonWindowSignals.freeWidth(in: window, sensors: duo.sensors), window.bounds.width)
        duo.hasBar = true
        XCTAssertEqual(FentonWindowSignals.railWidth(in: window, sensors: duo.sensors), window.safeAreaInsets.right)
        XCTAssertEqual(
            FentonWindowSignals.freeWidth(in: window, sensors: duo.sensors),
            window.bounds.width - window.safeAreaInsets.right
        )
    }

    // MARK: Hinge views

    private func makeHingeScene(_ duo: FakeDuo) throws -> (FentonWindowSignals, FentonWindowEnvironment, UIView) {
        let (signals, environment, host, _) = try makeSignals(duo)
        host.frame.size = host.superview?.bounds.size ?? host.frame.size
        return (signals, environment, host)
    }

    func testAvoidingViewStaysCentredUntilTheBandCrossesIt() throws {
        let duo = FakeDuo()
        let (signals, environment, host) = try makeHingeScene(duo)
        let object = UIView()
        let avoiding = FentonHingeAvoidingView(content: object, environment: environment, objectWidth: 200)
        avoiding.frame = host.bounds
        host.addSubview(avoiding)
        avoiding.layoutIfNeeded()
        XCTAssertEqual(object.frame.width, 200, accuracy: 0.01)
        XCTAssertEqual(object.frame.midX, host.bounds.midX, accuracy: 0.5, "no band: centred")

        duo.partlyFolded(in: host.bounds.size)
        signals.refresh()
        LaneBHost.spin()
        avoiding.layoutIfNeeded()
        let band = FentonHingeAvoidance.band(in: CGRect(x: 0, y: 0, width: host.bounds.width, height: 0), hinge: environment.band)
        let expected = FentonHingeAvoidance.placement(objectWidth: 200, containerWidth: host.bounds.width, band: band)
        XCTAssertEqual(object.frame.minX, expected.x, accuracy: 0.5)
        XCTAssertEqual(object.frame.width, expected.width, accuracy: 0.5)
        XCTAssertLessThanOrEqual(object.frame.maxX, duo.hinge?.minX ?? 0, "the object sits in the leading region")

        duo.flat(in: host.bounds.size)
        signals.refresh()
        LaneBHost.spin()
        avoiding.layoutIfNeeded()
        XCTAssertEqual(object.frame.midX, host.bounds.midX, accuracy: 0.5, "flat: centred again")
    }

    func testClearingViewTakesTheWiderSideOrTheLeadingRegion() throws {
        let duo = FakeDuo()
        let (signals, environment, host) = try makeHingeScene(duo)
        let form = UIView()
        let message = UIView()
        let clearing = FentonHingeClearingView(content: form, environment: environment)
        let leadingOnly = FentonHingeClearingView(content: message, environment: environment, leadingOnly: true)
        for view in [clearing, leadingOnly] {
            view.frame = host.bounds
            host.addSubview(view)
            view.layoutIfNeeded()
            XCTAssertEqual(view.content.frame, view.bounds, "no band: the whole container")
        }

        duo.partlyFolded(in: host.bounds.size)
        duo.hinge = CGRect(x: host.bounds.width * 0.6, y: 0, width: 2, height: host.bounds.height)
        signals.refresh()
        LaneBHost.spin()
        clearing.layoutIfNeeded()
        leadingOnly.layoutIfNeeded()
        let hinge = try XCTUnwrap(duo.hinge)
        XCTAssertEqual(form.frame.minX, 0, accuracy: 0.5, "the leading side is the wider one")
        XCTAssertEqual(form.frame.maxX, hinge.minX, accuracy: 1.5)
        XCTAssertEqual(message.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(message.frame.maxX, hinge.minX, accuracy: 1.5)
        XCTAssertNil(leadingOnly.hitTest(CGPoint(x: host.bounds.width - 2, y: 20), with: nil), "touches pass through beside the message")
    }
}
#endif
