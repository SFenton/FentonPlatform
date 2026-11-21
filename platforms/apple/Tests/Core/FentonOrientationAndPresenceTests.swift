import XCTest
@testable import FentonAppleCore

@MainActor
final class FentonOrientationAndPresenceTests: XCTestCase {
    private let info: [String: Any] = [
        "UISupportedInterfaceOrientations~iphone": ["UIInterfaceOrientationPortrait"],
        "UISupportedInterfaceOrientations~ipad": [
            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"
        ]
    ]

    func testPhoneIsPortraitOnlyAndTabletAllowsAll() {
        let phone = FentonOrientationPolicy.declared(in: info, isPad: false)
        XCTAssertEqual(FentonOrientationPolicy.supported(declared: phone, hasHinge: false), .portrait)
        XCTAssertEqual(FentonOrientationPolicy.supported(declared: phone, hasHinge: true), .all)
        let pad = FentonOrientationPolicy.declared(in: info, isPad: true)
        XCTAssertEqual(FentonOrientationPolicy.supported(declared: pad, hasHinge: false), .all)
        XCTAssertEqual(FentonOrientationPolicy.supported(declared: [], hasHinge: false), .portrait)
    }

    func testDeclaredFallsBackToTheUnsuffixedKeyThenEmpty() {
        let plain: [String: Any] = ["UISupportedInterfaceOrientations": ["UIInterfaceOrientationLandscapeLeft"]]
        XCTAssertEqual(FentonOrientationPolicy.declared(in: plain, isPad: false), .landscapeLeft)
        XCTAssertEqual(FentonOrientationPolicy.declared(in: [:], isPad: true), [])
        XCTAssertEqual(FentonOrientationPolicy.infoPlistKeys(isPad: true).first, "UISupportedInterfaceOrientations~ipad")
    }

    func testPlistParsingIgnoresUnknownNames() {
        let parsed = FentonSupportedOrientations(infoPlistValues: [
            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight", "Nonsense"
        ])
        XCTAssertEqual(parsed, .all)
        XCTAssertEqual(FentonSupportedOrientations(infoPlistValues: ["Nonsense"]), [])
        XCTAssertEqual(FentonSupportedOrientations(rawValue: 1), .portrait)
    }

    func testFirstHingeFiresOnceAndLaterNilIsIgnored() {
        var calls = 0
        let presence = FentonHingePresence { calls += 1 }
        presence.record(hinge: nil)
        XCTAssertFalse(presence.hasHinge)
        XCTAssertEqual(calls, 0)
        presence.record(hinge: .closed)
        presence.record(hinge: .fullyOpen)
        presence.record(hinge: nil, hasVerticalBar: true)
        presence.record(hinge: nil)
        XCTAssertTrue(presence.hasHinge)
        XCTAssertEqual(calls, 1)
    }

    func testAVerticalBarAloneCountsAsAHingeAndResetForgetsIt() {
        let presence = FentonHingePresence()
        presence.record(hinge: nil, hasVerticalBar: true)
        XCTAssertTrue(presence.hasHinge)
        presence.resetForTests()
        XCTAssertFalse(presence.hasHinge)
    }

    func testSharedInstanceAndHookReplacement() {
        var calls = 0
        let presence = FentonHingePresence.shared
        presence.resetForTests()
        presence.onFirstHinge = { calls += 1 }
        presence.record(hinge: .partiallyOpen)
        XCTAssertEqual(calls, 1)
        presence.onFirstHinge = {}
        presence.resetForTests()
    }
}
