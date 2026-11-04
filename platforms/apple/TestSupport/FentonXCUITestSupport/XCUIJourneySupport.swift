#if canImport(XCTest)
import XCTest

/// Runner-side helpers. This target intentionally has no UIKit fixture listener.
public enum FentonXCUITestSupport {
    public static func waitFor(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
    }

    public static func assertVisible(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists && element.isHittable, file: file, line: line)
    }
}
#endif
