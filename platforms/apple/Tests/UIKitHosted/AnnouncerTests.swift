#if os(iOS)
import FentonUIKit
import XCTest

@MainActor
final class AnnouncerTests: XCTestCase {
    private var spoken: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        spoken = []
        FentonAnnouncer.sink = { [weak self] in self?.spoken.append($0) }
    }

    override func tearDown() async throws {
        FentonAnnouncer.sink = nil
        try await super.tearDown()
    }

    func testAnnounceSpeaksTheTextAndIgnoresEmptyText() {
        FentonAnnouncer.announce("Saved")
        FentonAnnouncer.announce("")
        XCTAssertEqual(spoken, ["Saved"])
    }

    func testScreenChangedWithAndWithoutText() {
        FentonAnnouncer.screenChanged()
        FentonAnnouncer.screenChanged(announcing: "Home")
        XCTAssertEqual(spoken, ["screenChanged", "screenChanged: Home"])
    }

    func testLayoutChangedNamesTheElementThatTakesFocus() {
        let element = NSObject()
        element.accessibilityLabel = "Menu"
        FentonAnnouncer.layoutChanged(focus: element)
        FentonAnnouncer.layoutChanged(focus: "Panel")
        FentonAnnouncer.layoutChanged(focus: nil)
        XCTAssertEqual(spoken, ["layoutChanged: Menu", "layoutChanged: Panel", "layoutChanged"])
    }
}
#endif
