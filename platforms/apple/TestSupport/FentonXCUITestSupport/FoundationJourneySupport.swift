#if canImport(XCTest)
import XCTest

/// Runner-side helpers for the foundation journeys: launching a fixture in a pose and a text size, rotating, the leading-edge swipe
/// back, waiting for an element to stop moving, and measuring that a heading is not clipped. Everything is a plain `XCUIElement` or
/// `XCUIApplication` call: the target has no UIKit fixture listener.
@MainActor
public extension FentonXCUITestSupport {
    // MARK: - Launching

    /// The content size category launch value for the largest accessibility text size (AX XXXL).
    static let largestAccessibilityTextSize = "UICTContentSizeCategoryAccessibilityXXXL"

    /// Launches the app with `arguments`, optionally at the largest accessibility text size.
    /// - Parameters:
    ///   - arguments: Launch arguments for the fixture (for example `--foundation`).
    ///   - largestText: Launch at AX XXXL (`-UIPreferredContentSizeCategoryName`).
    /// - Returns: The running application.
    @discardableResult
    static func launch(_ arguments: [String], largestText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var all = arguments
        if largestText { all += ["-UIPreferredContentSizeCategoryName", largestAccessibilityTextSize] }
        app.launchArguments = all
        app.launch()
        return app
    }

    // MARK: - Poses

    #if os(iOS)
    /// Rotates the device and waits for the window to take the new shape.
    /// - Parameters:
    ///   - orientation: The pose to rotate to.
    ///   - app: The application whose window must change shape.
    static func rotate(to orientation: UIDeviceOrientation, in app: XCUIApplication) {
        let before = app.windows.firstMatch.frame.size
        XCUIDevice.shared.orientation = orientation
        let wantsLandscape = orientation.isLandscape
        let predicate = NSPredicate { _, _ in
            let size = app.windows.firstMatch.frame.size
            return (size.width > size.height) == wantsLandscape && (size != before || wantsLandscape == (before.width > before.height))
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        _ = XCTWaiter.wait(for: [expectation], timeout: 10)
    }
    #endif

    // MARK: - Gestures

    /// Swipes from the leading screen edge toward the trailing edge: the system's and the foundation's Back gesture.
    static func edgeSwipeBack(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 2, dy: 0))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    // MARK: - Waiting

    /// Waits until `element` exists and its frame has not moved between two looks 0.15 s apart: a slide or a column move has settled.
    static func waitUntilStable(_ element: XCUIElement, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("\(element) did not appear", file: file, line: line)
            return
        }
        let end = Date().addingTimeInterval(timeout)
        var last = element.frame
        while Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let now = element.frame
            if now == last { return }
            last = now
        }
        XCTFail("\(element) kept moving", file: file, line: line)
    }

    /// Waits until `element` no longer exists.
    static func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed, "\(element) is still there", file: file, line: line)
    }

    // MARK: - Measuring

    /// Asserts that `element` is on screen and its frame lies inside the window with some width: a heading that is clipped or pushed
    /// off the edge fails.
    /// - Parameter vertically: Also require the frame to end above the window's bottom edge; false for text that wraps onto many
    ///   lines inside a scroll view, which is whole but may run past the screen.
    static func assertNotClipped(_ element: XCUIElement, in app: XCUIApplication, vertically: Bool = true,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, "\(element) is missing", file: file, line: line)
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        XCTAssertGreaterThan(frame.width, 1, "\(element) has no width", file: file, line: line)
        XCTAssertGreaterThan(frame.height, 1, "\(element) has no height", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "\(element) starts left of the window", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(element) ends right of the window", file: file, line: line)
        guard vertically else { return }
        XCTAssertGreaterThanOrEqual(frame.minY, window.minY - 0.5, "\(element) starts above the window", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, window.maxY + 0.5, "\(element) ends below the window", file: file, line: line)
    }

    /// Any element, whatever its type, found by identifier: a container view that carries an identifier has no fixed element type.
    static func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
}
#endif
