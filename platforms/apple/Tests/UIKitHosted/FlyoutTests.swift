#if os(iOS)
import FentonAppleCore
@testable import FentonUIKit
import UIKit
import XCTest

@MainActor
final class FlyoutTests: XCTestCase {
    private var window: UIWindow?
    private var dismissals = 0
    private var selections: [String] = []
    private var spoken: [String] = []

    private let destinations = [
        FentonFlyoutDestination(id: "home", title: "Home", symbol: "house", identifier: "row.home"),
        FentonFlyoutDestination(id: "chores", title: "Chores", symbol: "checkmark.circle", identifier: "row.chores", badge: "3", spokenLabel: "Chores, 3 overdue")
    ]

    override func setUp() async throws {
        try await super.setUp()
        dismissals = 0
        selections = []
        spoken = []
        FentonAnnouncer.sink = { [weak self] in self?.spoken.append($0) }
    }

    override func tearDown() async throws {
        FentonAnnouncer.sink = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func makeFlyout() throws -> FentonFlyoutView {
        let flyout = FentonFlyoutView(
            environment: FentonWindowEnvironment(),
            onDismiss: { [unowned self] in dismissals += 1 },
            onSelect: { [unowned self] in selections.append($0) }
        )
        let root = UIViewController()
        window = try LaneBHost.window(showing: root)
        flyout.frame = root.view.bounds
        root.view.addSubview(flyout)
        flyout.setDestinations(destinations, selected: "home")
        flyout.layoutIfNeeded()
        return flyout
    }

    private func panel(of flyout: FentonFlyoutView) throws -> FentonFlyoutPanel {
        try XCTUnwrap(flyout.subviews.compactMap { $0 as? FentonFlyoutPanel }.first)
    }

    private func rows(in view: UIView) -> [FentonFlyoutRow] {
        view.subviews.flatMap { sub in (sub as? FentonFlyoutRow).map { [$0] } ?? rows(in: sub) }
    }

    // MARK: Touches

    func testAClosedFlyoutLetsEveryTouchThrough() throws {
        let flyout = try makeFlyout()
        XCTAssertFalse(flyout.isBlockingTouches)
        XCTAssertNil(flyout.hitTest(CGPoint(x: 10, y: 100), with: nil))
        XCTAssertNil(flyout.hitTest(CGPoint(x: flyout.bounds.maxX - 5, y: 300), with: nil))
    }

    func testAnOpenFlyoutsShieldBlocksEveryTouchUnderIt() throws {
        let flyout = try makeFlyout()
        flyout.open(animated: false)
        XCTAssertTrue(flyout.isOpen)
        XCTAssertTrue(flyout.isBlockingTouches)
        // Under the status bar, beside the panel, and low in the window: something here answers, so nothing beneath does.
        for point in [CGPoint(x: flyout.bounds.maxX - 4, y: 4), CGPoint(x: flyout.bounds.maxX - 4, y: flyout.bounds.midY), CGPoint(x: 4, y: flyout.bounds.maxY - 4)] {
            XCTAssertNotNil(flyout.hitTest(point, with: nil), "\(point)")
        }
        let panel = try panel(of: flyout)
        let inside = flyout.hitTest(CGPoint(x: 8, y: flyout.bounds.midY), with: nil)
        XCTAssertTrue(inside?.isDescendant(of: panel) ?? false)
    }

    func testTheScrimBesideThePanelAsksToClose() throws {
        let flyout = try makeFlyout()
        flyout.open(animated: false)
        let panel = try panel(of: flyout)
        let scrim = flyout.hitTest(CGPoint(x: panel.frame.maxX + 6, y: flyout.bounds.midY), with: nil)
        let button = try XCTUnwrap(scrim as? UIButton)
        XCTAssertEqual(button.accessibilityIdentifier, "flyout.scrim")
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(dismissals, 1)
    }

    // MARK: Accessibility

    func testTheOpenPanelIsModalForVoiceOverAndEscapeAsksToClose() throws {
        let flyout = try makeFlyout()
        let panel = try panel(of: flyout)
        XCTAssertTrue(panel.accessibilityViewIsModal)
        XCTAssertFalse(panel.isAccessibilityElement)
        XCTAssertTrue(panel.accessibilityPerformEscape())
        XCTAssertEqual(dismissals, 1)
        XCTAssertTrue(panel.heading.accessibilityTraits.contains(.header))
    }

    func testClosingAnnouncesTheLayoutChangeToTheReturnElement() throws {
        let flyout = try makeFlyout()
        let menu = NSObject()
        menu.accessibilityLabel = "Menu"
        flyout.returnFocusElement = menu
        flyout.open(animated: false)
        XCTAssertTrue(spoken.isEmpty, "opening moves focus to the heading, not through the announcer")
        flyout.close(animated: false)
        XCTAssertEqual(spoken, ["layoutChanged: Menu"])
        XCTAssertFalse(flyout.isOpen)
        XCTAssertFalse(flyout.isBlockingTouches)
        XCTAssertNil(flyout.hitTest(CGPoint(x: 10, y: 100), with: nil))
        flyout.close(animated: false)
        XCTAssertEqual(spoken.count, 1, "closing twice announces once")
    }

    func testAnimatedCloseKeepsBlockingUntilItHasSettled() throws {
        let flyout = try makeFlyout()
        flyout.open(animated: false)
        flyout.close(animated: true)
        XCTAssertTrue(flyout.isBlockingTouches, "a tap during the slide must not reach the page")
        XCTAssertTrue(LaneBHost.spin(until: { !flyout.isBlockingTouches }))
        let panel = try panel(of: flyout)
        XCTAssertTrue(panel.isHidden)
    }

    func testAnimatedOpenEndsWithThePanelAtTheLeadingEdge() throws {
        let flyout = try makeFlyout()
        flyout.open(animated: true)
        let panel = try panel(of: flyout)
        XCTAssertTrue(LaneBHost.spin(until: { panel.frame.minX == 0 && flyout.subviews.contains { $0.alpha == 1 && $0 !== panel } }))
        XCTAssertEqual(panel.frame.minX, 0, accuracy: 0.5)
    }

    // MARK: Rows

    func testRowsShowTheDestinationsTheCurrentOneSelectedAndTheSpokenLabel() throws {
        let flyout = try makeFlyout()
        let rows = rows(in: try panel(of: flyout))
        XCTAssertEqual(rows.map(\.destination.id), ["home", "chores"])
        XCTAssertEqual(rows.map(\.accessibilityIdentifier), ["row.home", "row.chores"])
        XCTAssertTrue(rows[0].accessibilityTraits.contains(.selected))
        XCTAssertFalse(rows[1].accessibilityTraits.contains(.selected))
        XCTAssertEqual(rows[0].accessibilityLabel, "Home")
        XCTAssertEqual(rows[1].accessibilityLabel, "Chores, 3 overdue")
    }

    func testChoosingARowReportsItsIdentifier() throws {
        let flyout = try makeFlyout()
        let rows = rows(in: try panel(of: flyout))
        rows[1].sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, ["chores"])
    }

    func testSettingTheSameDestinationsKeepsTheRowsAndMovesTheSelection() throws {
        let flyout = try makeFlyout()
        let panel = try panel(of: flyout)
        let before = rows(in: panel)
        flyout.setDestinations(destinations, selected: "chores")
        let after = rows(in: panel)
        XCTAssertEqual(before.map { ObjectIdentifier($0) }, after.map { ObjectIdentifier($0) }, "surviving rows are updated in place")
        XCTAssertTrue(after[1].accessibilityTraits.contains(.selected))
        XCTAssertFalse(after[0].accessibilityTraits.contains(.selected))
    }

    func testTitleAndCloseLabelAreTheAppsCopy() throws {
        let flyout = try makeFlyout()
        flyout.title = "Menu"
        flyout.closeLabel = "Dismiss"
        XCTAssertEqual(try panel(of: flyout).heading.text, "Menu")
        XCTAssertEqual(flyout.subviews.compactMap { $0 as? UIButton }.first?.accessibilityLabel, "Dismiss")
    }

    // MARK: Width

    func testPanelWidthKeepsToTheShareOrTakesNarrowWindowsWhole() {
        XCTAssertEqual(FentonFlyoutView.panelWidth(preferred: 300, available: 400), 300)
        XCTAssertEqual(FentonFlyoutView.panelWidth(preferred: 500, available: 400), 400, "a narrow window gives the words all of it")
        XCTAssertEqual(FentonFlyoutView.panelWidth(preferred: 700, available: 1000), 700)
        XCTAssertEqual(FentonFlyoutView.panelWidth(preferred: 900, available: 1000), 800, "wide: 80 percent, a scrim strip stays")
    }
}
#endif
