import FentonXCUITestSupport
import XCTest

/// The foundation fixture, driven as a person would: push and swipe back, split and rotate, a sheet, large text, the flyout.
/// Duo postures are not here: they need a folding device and go through the shared pose tool (see `docs/apple/foundation.md`).
@MainActor
final class FoundationJourneys: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func launch(largestText: Bool = false) -> XCUIApplication {
        FentonXCUITestSupport.launch(["--foundation"], largestText: largestText)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        FentonXCUITestSupport.element(identifier, in: app)
    }

    // MARK: 1. Push, swipe back, no reload

    func testPushingADetailAndSwipingBackKeepsTheListWhereItWas() {
        let app = launch()
        let list = app.collectionViews["foundation.list"]
        FentonXCUITestSupport.waitFor(list)
        list.swipeUp()
        list.swipeUp()
        let row = list.cells.element(boundBy: 3)
        FentonXCUITestSupport.waitUntilStable(row)
        let identifier = row.identifier
        XCTAssertTrue(identifier.hasPrefix("foundation.row."), "a row of the list: \(identifier)")
        let before = row.frame

        row.tap()
        let title = element("foundation.detail.title", in: app)
        FentonXCUITestSupport.waitUntilStable(title)
        XCTAssertFalse(list.exists && list.isHittable && list.cells[identifier].isHittable, "the list is under the pushed page")

        FentonXCUITestSupport.edgeSwipeBack(in: app)
        let again = app.collectionViews["foundation.list"].cells[identifier]
        FentonXCUITestSupport.waitUntilStable(again)
        XCTAssertTrue(again.isHittable, "the same row is back")
        XCTAssertEqual(again.frame.minY, before.minY, accuracy: 1, "the list kept its scroll offset: it did not reload")
    }

    // MARK: 2. Split and rotate (iPad)

    func testIPadLandscapeSplitsAndPortraitPushesTheSamePageWithNoLoss() throws {
        try XCTSkipUnless(isPad, "a phone never splits")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch()
        FentonXCUITestSupport.rotate(to: .landscapeLeft, in: app)
        let list = app.collectionViews["foundation.list"]
        FentonXCUITestSupport.waitUntilStable(list)
        list.cells["foundation.row.3"].tap()

        let trailing = element("split.trailing", in: app)
        FentonXCUITestSupport.waitUntilStable(trailing)
        FentonXCUITestSupport.waitUntilStable(list)
        let window = app.windows.firstMatch.frame
        let band: CGFloat = 1
        XCTAssertEqual(list.frame.width + band + trailing.frame.width, window.width, accuracy: 2, "the two columns fill the container")
        XCTAssertGreaterThanOrEqual(list.frame.width, 360)
        XCTAssertGreaterThanOrEqual(trailing.frame.width, 360)
        XCTAssertTrue(element("foundation.detail.title", in: app).exists)
        XCTAssertEqual(element("foundation.detail.title", in: app).label, "Item 3")

        FentonXCUITestSupport.rotate(to: .portrait, in: app)
        let pushed = element("foundation.detail.title", in: app)
        FentonXCUITestSupport.waitUntilStable(pushed)
        XCTAssertEqual(pushed.label, "Item 3", "the same page, now pushed")
        XCTAssertFalse(element("split.trailing", in: app).exists, "no column when the window does not split")
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists, "the stack has a Back")

        FentonXCUITestSupport.rotate(to: .landscapeLeft, in: app)
        let back = element("split.trailing", in: app)
        FentonXCUITestSupport.waitUntilStable(back)
        XCTAssertEqual(element("foundation.detail.title", in: app).label, "Item 3", "and it is a column again")
    }

    // MARK: 3. Sheet

    func testTheSheetIsAPageSheetAndDismisses() {
        let app = launch()
        FentonXCUITestSupport.waitFor(app.collectionViews["foundation.list"])
        app.buttons["foundation.open-sheet"].tap()
        let title = app.staticTexts["foundation.sheet.title"]
        FentonXCUITestSupport.waitFor(title)
        XCTAssertEqual(app.staticTexts["foundation.sheet.style"].label, "pageSheet", "presented through FentonSheetPresenter as a page sheet")
        app.buttons["foundation.sheet.close"].tap()
        FentonXCUITestSupport.waitFor(app.collectionViews["foundation.list"])
        FentonXCUITestSupport.waitForDisappearance(title)
    }

    // MARK: 4. Largest text

    func testLargestAccessibilityTextDoesNotClipTheTitleOrTheDetailHeading() {
        let app = launch(largestText: true)
        FentonXCUITestSupport.waitFor(app.collectionViews["foundation.list"])
        let title = app.navigationBars.staticTexts["Foundation"]
        FentonXCUITestSupport.waitUntilStable(title)
        FentonXCUITestSupport.assertNotClipped(title, in: app)

        let row = app.collectionViews["foundation.list"].cells.element(boundBy: 0)
        FentonXCUITestSupport.waitUntilStable(row)
        row.tap()
        let heading = element("foundation.detail.title", in: app)
        FentonXCUITestSupport.waitUntilStable(heading)
        FentonXCUITestSupport.assertNotClipped(heading, in: app)
        let body = element("foundation.detail.body", in: app)
        FentonXCUITestSupport.assertNotClipped(body, in: app, vertically: false)
    }

    // MARK: 5. Flyout

    func testTheFlyoutIsModalAndClosesBack() {
        let app = launch()
        let list = app.collectionViews["foundation.list"]
        FentonXCUITestSupport.waitFor(list)
        XCTAssertTrue(list.cells["foundation.row.0"].exists)

        app.buttons["foundation.menu"].tap()
        let first = element("foundation.flyout.first", in: app)
        FentonXCUITestSupport.waitUntilStable(first)
        XCTAssertTrue(element("flyout", in: app).exists)
        XCTAssertTrue(element("flyout.scrim", in: app).exists, "the close target beside the panel is reachable after its rows")
        // The VoiceOver-modal flag is not visible to the runner; `FoundationHostedTests` asserts it on this very fixture.

        // Beside the panel the scrim closes it (the panel's own Close button appears only at accessibility text sizes).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        XCTAssertTrue(list.cells["foundation.row.0"].waitForExistence(timeout: 5), "closing gives the page back")
        FentonXCUITestSupport.waitForDisappearance(first)
    }
}
