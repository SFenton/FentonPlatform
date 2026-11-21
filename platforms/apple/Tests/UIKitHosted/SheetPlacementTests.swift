#if os(iOS)
import FentonAppleCore
@testable import FentonUIKit
import UIKit
import XCTest

@MainActor
final class SheetPlacementTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var presence = FentonHingePresence()
    private let duo = FakeDuo()

    override func setUp() async throws {
        try await super.setUp()
        presence = FentonHingePresence()
    }

    override func tearDown() async throws {
        windows.forEach { $0.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    private func makeWindow() throws -> (UIWindow, UIViewController) {
        let root = UIViewController()
        let window = try LaneBHost.window(showing: root)
        windows.append(window)
        return (window, root)
    }

    private func makeSheet(_ controller: UIViewController = UIViewController()) -> (UIViewController, UISheetPresentationController?) {
        controller.modalPresentationStyle = .pageSheet
        return (controller, controller.sheetPresentationController)
    }

    // MARK: Full height

    func testFillsHeightOnlyWithAHingeAndAVerticalBandOrNoBand() throws {
        let (window, _) = try makeWindow()
        let size = window.bounds.size
        XCTAssertFalse(FentonSheetPlacement.fillsHeight(in: window, presence: presence, sensors: duo.sensors), "no hinge: today's behaviour")

        duo.partlyFolded(in: size)
        XCTAssertTrue(FentonSheetPlacement.fillsHeight(in: window, presence: presence, sensors: duo.sensors), "vertical band")
        duo.flat(in: size)
        XCTAssertTrue(FentonSheetPlacement.fillsHeight(in: window, presence: presence, sensors: duo.sensors), "flat is a vertical band too")

        duo.hinge = CGRect(x: 0, y: size.height / 2, width: size.width, height: 2)
        XCTAssertFalse(FentonSheetPlacement.fillsHeight(in: window, presence: presence, sensors: duo.sensors), "horizontal band: unfolded portrait")
    }

    func testTheFoldedOuterScreenFillsHeightOnceTheDeviceIsKnownToHaveAHinge() throws {
        let (window, _) = try makeWindow()
        XCTAssertFalse(FentonSheetPlacement.fillsHeight(in: window, presence: presence, sensors: duo.sensors))
        presence.record(hinge: .closed)
        XCTAssertTrue(FentonSheetPlacement.fillsHeight(in: window, presence: presence, sensors: duo.sensors))
        XCTAssertTrue(FentonSheetPlacement.fillsHeight(in: nil, presence: presence, sensors: duo.sensors), "no view: the device record only")
    }

    func testAVerticalBarOnAnyViewTeachesPresence() throws {
        let (window, _) = try makeWindow()
        duo.hasBar = true
        XCTAssertFalse(presence.hasHinge)
        XCTAssertTrue(FentonSheetPlacement.hasHinge(in: window, presence: presence, sensors: duo.sensors))
        XCTAssertTrue(presence.hasHinge)
    }

    // MARK: Leading half

    func testLeadingHalfSizeIsFullHeightLessTheMarginAndEndsAtTheHinge() throws {
        let (window, _) = try makeWindow()
        XCTAssertNil(FentonSheetPlacement.leadingHalfSize(in: window, sensors: duo.sensors), "no hinge")
        XCTAssertNil(FentonSheetPlacement.leadingHalfSize(in: nil, sensors: duo.sensors))
        XCTAssertNil(FentonSheetPlacement.leadingHalfSize(in: UIView(), sensors: duo.sensors), "no window")

        let size = window.bounds.size
        duo.partlyFolded(in: size)
        let hinge = try XCTUnwrap(duo.hinge)
        let half = try XCTUnwrap(FentonSheetPlacement.leadingHalfSize(in: window, sensors: duo.sensors))
        XCTAssertEqual(half.width, (hinge.minX - FentonSheetPolicy.halfMargin).rounded(.down))
        XCTAssertEqual(half.height, (size.height - 2 * FentonSheetPolicy.halfMargin).rounded(.down))

        duo.flat(in: size)
        let flat = try XCTUnwrap(FentonSheetPlacement.leadingHalfSize(in: window, sensors: duo.sensors))
        XCTAssertEqual(flat.width, max(0, ((size.width - FentonSheetPolicy.midpointBand) / 2 - FentonSheetPolicy.halfMargin).rounded(.down)))
    }

    // MARK: Place

    func testLeadingPlacementOnlyWithAHinge() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("preferredPlacement is iOS 27") }
        let (window, _) = try makeWindow()
        let (controller, sheet) = makeSheet()
        defer { withExtendedLifetime(controller) {} }
        FentonSheetPlacement.place(sheet, in: window, presence: presence, sensors: duo.sensors)
        XCTAssertEqual(sheet?.preferredPlacement, .automatic, "a phone without a hinge, and an iPad, keep the system's")

        duo.partlyFolded(in: window.bounds.size)
        FentonSheetPlacement.place(sheet, in: window, presence: presence, sensors: duo.sensors)
        XCTAssertEqual(sheet?.preferredPlacement, .leading)
        FentonSheetPlacement.place(nil, in: window, presence: presence, sensors: duo.sensors)
    }

    func testBesideAVerticalHingeTheSheetIsSizedToTheLeadingHalfThroughPreferredContentSize() throws {
        let (window, _) = try makeWindow()
        let (controller, sheet) = makeSheet()
        controller.preferredContentSize = CGSize(width: 320, height: 500)
        duo.partlyFolded(in: window.bounds.size)
        let half = try XCTUnwrap(FentonSheetPlacement.leadingHalfSize(in: window, sensors: duo.sensors))

        FentonSheetPlacement.place(sheet, in: window, presence: presence, sensors: duo.sensors)
        XCTAssertEqual(sheet?.prefersPageSizing, false)
        XCTAssertEqual(controller.preferredContentSize, half)

        duo.hinge = nil
        FentonSheetPlacement.place(sheet, in: window, presence: presence, sensors: duo.sensors)
        XCTAssertEqual(sheet?.prefersPageSizing, true, "page sizing returns off the half")
        XCTAssertEqual(controller.preferredContentSize, CGSize(width: 320, height: 500), "the sheet's own size returns")
    }

    func testANavigationControllersBarHeightIsTakenOffSoThePresentedSheetReadsTheHalfBack() throws {
        let (window, root) = try makeWindow()
        let navigation = UINavigationController(rootViewController: UIViewController())
        let (_, sheet) = makeSheet(navigation)
        duo.partlyFolded(in: window.bounds.size)
        root.present(navigation, animated: false)
        let presented = try XCTUnwrap(sheet)
        _ = presented
        let half = try XCTUnwrap(FentonSheetPlacement.leadingHalfSize(in: window, sensors: duo.sensors))

        FentonSheetPlacement.setContentSize(half, on: navigation)
        XCTAssertEqual(navigation.preferredContentSize.height, half.height, accuracy: 0.5, "the bar is not added on top of the half")
        XCTAssertEqual(navigation.preferredContentSize.width, half.width, accuracy: 0.5)
        root.dismiss(animated: false)
    }

    // MARK: Pose watch

    func testPoseWatchSeesAFoldOrAnUnfoldAndNotARepeat() throws {
        let (window, _) = try makeWindow()
        var watch = FentonSheetPlacement.PoseWatch(presence: presence, sensors: duo.sensors)
        XCTAssertFalse(watch.changed(in: window), "nothing recorded: the first layout is not a change")

        watch.record(in: window)
        XCTAssertFalse(watch.changed(in: window), "unchanged")

        let size = window.bounds.size
        duo.hinge = CGRect(x: size.width * 0.6, y: 0, width: 2, height: size.height)
        duo.isActive = true
        XCTAssertTrue(watch.changed(in: window), "a hinge appeared")
        XCTAssertFalse(watch.changed(in: window), "the new pose is now the recorded one")

        duo.isActive = false
        XCTAssertTrue(watch.changed(in: window), "partly folded to flat changes the half's width")
    }

    // MARK: Presenter

    func testPresenterConfiguresDetentsAndKeepsTheSystemWhenAskedTo() throws {
        let controller = UIViewController()
        FentonSheetPresenter.configure(controller, configuration: .init(heightPolicy: .medium, placement: .system))
        XCTAssertEqual(controller.modalPresentationStyle, .pageSheet)
        XCTAssertEqual(controller.sheetPresentationController?.detents.count, 1)
        XCTAssertEqual(FentonSheetConfiguration().placement, .duoAware, "hinge placement is the default")
        XCTAssertEqual(FentonSheetConfiguration().heightPolicy, .mediumAndLarge)
    }

    func testDuoAwarePresenterTakesTheLargeDetentOnlyWhereTheRuleSaysEverySheetFillsTheHeight() throws {
        let (window, _) = try makeWindow()
        let plain = UIViewController()
        FentonSheetPresenter.configure(plain, in: window)
        XCTAssertGreaterThanOrEqual(plain.sheetPresentationController?.detents.count ?? 0, 1)

        // The system sensors report no hinge in the simulator; a recorded device hinge with no view reads as folded.
        FentonHingePresence.shared.record(hinge: .closed)
        defer { FentonHingePresence.shared.resetForTests() }
        let folded = UIViewController()
        FentonSheetPresenter.configure(folded, configuration: .init(heightPolicy: .mediumAndLarge), in: nil)
        XCTAssertEqual(folded.sheetPresentationController?.detents.count, 1)
    }

    func testThePresenterTakesAnInjectedPresenceInsteadOfTheSharedOne() throws {
        let presence = FentonHingePresence()
        presence.record(hinge: .closed)
        let folded = UIViewController()
        FentonSheetPresenter.configure(folded, in: nil, presence: presence)
        XCTAssertEqual(folded.sheetPresentationController?.detents.count, 1, "the injected record says folded")
        XCTAssertFalse(FentonHingePresence.shared.hasHinge, "the shared record was never touched")
    }

    func testTheSheetConfigurationIsAPlainValueAnyThreadMayBuild() async {
        let configuration = await Task.detached { FentonSheetConfiguration(showsGrabber: false) }.value
        XCTAssertFalse(configuration.showsGrabber)
    }
}
#endif
