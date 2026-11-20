#if os(iOS)
import FentonAppleCore
@testable import FentonUIKit
import UIKit
import XCTest

/// A window root that counts how often it was asked to re-read its orientations.
@MainActor
private final class OrientationSpyController: UIViewController {
    private(set) var requests = 0
    override func setNeedsUpdateOfSupportedInterfaceOrientations() {
        requests += 1
        super.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

@MainActor
final class OrientationSupportTests: XCTestCase {
    private let info: [String: Any] = [
        "UISupportedInterfaceOrientations~iphone": ["UIInterfaceOrientationPortrait"],
        "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft"]
    ]

    func testEveryOrientationMapsToItsUIKitMask() {
        XCTAssertEqual(FentonOrientationSupport.mask(for: FentonSupportedOrientations.portrait), .portrait)
        XCTAssertEqual(FentonOrientationSupport.mask(for: FentonSupportedOrientations.portraitUpsideDown), .portraitUpsideDown)
        XCTAssertEqual(FentonOrientationSupport.mask(for: FentonSupportedOrientations.landscapeLeft), .landscapeLeft)
        XCTAssertEqual(FentonOrientationSupport.mask(for: FentonSupportedOrientations.landscapeRight), .landscapeRight)
        XCTAssertEqual(FentonOrientationSupport.mask(for: FentonSupportedOrientations.all), .all)
        XCTAssertEqual(FentonOrientationSupport.mask(for: FentonSupportedOrientations([.portrait, .landscapeRight])), [.portrait, .landscapeRight])
        XCTAssertEqual(FentonOrientationSupport.mask(for: FentonSupportedOrientations([])), [])
    }

    func testTheMaskReadsTheDeclarationForTheIdiomAndOpensUpWithAHinge() {
        let presence = FentonHingePresence()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let expected: UIInterfaceOrientationMask = isPad ? [.portrait, .landscapeLeft] : .portrait
        XCTAssertEqual(FentonOrientationSupport.mask(for: nil, presence: presence, info: info), expected)
        XCTAssertEqual(FentonOrientationSupport.mask(for: nil, presence: presence, info: [:]), .portrait, "nothing declared is portrait")
        presence.record(hinge: .closed)
        XCTAssertEqual(FentonOrientationSupport.mask(for: nil, presence: presence, info: info), .all, "a hinge allows every orientation")
    }

    func testTheFirstHingeAsksEveryWindowsRootToReadItsOrientationsAgainOnce() {
        let presence = FentonHingePresence()
        let spy = OrientationSpyController()
        let window = pageTestWindow(spy)
        defer { window.isHidden = true }
        FentonOrientationSupport.install(on: presence) { [window] }
        FentonOrientationSupport.install(on: presence) { [window] }
        presence.record(hinge: nil)
        XCTAssertEqual(spy.requests, 0, "no hinge, no request")
        presence.record(hinge: .closed)
        XCTAssertEqual(spy.requests, 1, "the first hinge asks")
        presence.record(hinge: .fullyOpen)
        presence.record(hinge: nil)
        XCTAssertEqual(spy.requests, 1, "later readings do not")
    }

    func testTheInstallKeepsWhatOnFirstHingeAlreadyDid() {
        let presence = FentonHingePresence()
        var earlier = 0
        presence.onFirstHinge = { earlier += 1 }
        FentonOrientationSupport.install(on: presence) { [] }
        presence.record(hinge: nil, hasVerticalBar: true)
        XCTAssertEqual(earlier, 1)
    }

    func testTheRootAnswersTheMaskAndItOpensAfterTheFirstHinge() {
        let presence = FentonHingePresence()
        let root = FentonRootViewController(launchGround: .black, presence: presence, sensors: FakeDuo().sensors)
        XCTAssertEqual(root.supportedInterfaceOrientations, FentonOrientationSupport.mask(for: nil, presence: presence))
        presence.record(hinge: .closed)
        XCTAssertEqual(root.supportedInterfaceOrientations, .all)
    }

    func testTheApplicationDelegateWidensItsAnswerAfterTheFirstHinge() {
        final class Delegate: FentonApplicationDelegate {
            let record = FentonHingePresence()
            override var presence: FentonHingePresence { record }
        }
        let delegate = Delegate()
        let before = delegate.application(UIApplication.shared, supportedInterfaceOrientationsFor: nil)
        XCTAssertEqual(before, FentonOrientationSupport.mask(for: nil, presence: FentonHingePresence()), "the declaration until a hinge")
        XCTAssertNotEqual(before, .all, "narrower than a hinge allows")
        delegate.record.record(hinge: .closed)
        XCTAssertEqual(delegate.application(UIApplication.shared, supportedInterfaceOrientationsFor: nil), .all, "a hinge widens it")
    }
}
#endif
