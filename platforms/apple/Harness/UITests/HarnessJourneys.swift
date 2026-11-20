import XCTest
import FentonXCUITestSupport

final class HarnessJourneys: XCTestCase {
    func testInitialLaunchRendersPopulatedPage() {
        let app = XCUIApplication()
        app.launch()
        FentonXCUITestSupport.waitFor(app.tables["populated-page"])
        FentonXCUITestSupport.assertVisible(app.tables["populated-page"])
        XCTAssertTrue(app.buttons["open-sheet"].exists)
    }

    func testPopulatedPageAndSheetJourney() {
        let app = XCUIApplication()
        app.launchArguments = ["--ocean"]
        app.launch()
        FentonXCUITestSupport.waitFor(app.tables["populated-page"])
        FentonXCUITestSupport.assertVisible(app.tables["populated-page"])
        app.buttons["open-sheet"].tap()
        FentonXCUITestSupport.waitFor(app.staticTexts["sheet-title"])
        FentonXCUITestSupport.assertVisible(app.staticTexts["sheet-title"])
        app.buttons["sheet-close"].tap()
        FentonXCUITestSupport.waitFor(app.tables["populated-page"])
    }

    func testLargeTextJourney() {
        let app = XCUIApplication()
        app.launchArguments = ["--sunset"]
        app.launch()
        FentonXCUITestSupport.waitFor(app.tables["populated-page"])
        app.tables["populated-page"].swipeUp()
        XCTAssertTrue(app.tables["populated-page"].exists)
    }
    func testAX5LargeTextSheetCloseJourney() {
        let app = XCUIApplication()
        app.launchArguments = ["--sunset", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        FentonXCUITestSupport.waitFor(app.tables["populated-page"])
        FentonXCUITestSupport.assertVisible(app.tables["populated-page"])
        app.buttons["open-sheet"].tap()
        FentonXCUITestSupport.waitFor(app.staticTexts["sheet-title"])
        FentonXCUITestSupport.assertVisible(app.staticTexts["sheet-title"])
        XCTAssertTrue(app.buttons["sheet-close"].exists)
        app.buttons["sheet-close"].tap()
        FentonXCUITestSupport.waitFor(app.tables["populated-page"])
        FentonXCUITestSupport.assertVisible(app.tables["populated-page"])
    }
}
