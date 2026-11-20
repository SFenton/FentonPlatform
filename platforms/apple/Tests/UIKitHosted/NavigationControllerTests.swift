#if os(iOS)
import FentonAppleCore
@testable import FentonUIKit
import UIKit
import XCTest

@MainActor
final class NavigationControllerTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    private func makeStack(_ count: Int = 3, show: Bool = false) -> (FentonNavigationController, [UIViewController]) {
        let pages = (0..<count).map { index -> UIViewController in
            let page = UIViewController()
            page.title = "page \(index)"
            return page
        }
        let navigation = FentonNavigationController(rootViewController: pages[0])
        for page in pages.dropFirst() { navigation.pushViewController(page, animated: false) }
        if show { windows.append(pageTestWindow(navigation)) }
        return (navigation, pages)
    }

    // MARK: - Plain behaviour

    func testWithoutAnAdmissionClosureItIsAPlainNavigationController() {
        let (navigation, pages) = makeStack()
        XCTAssertTrue(navigation.popViewController(animated: false) === pages[2])
        XCTAssertEqual(navigation.popToRootViewController(animated: false)?.count, 1)
        XCTAssertEqual(navigation.viewControllers, [pages[0]])
        XCTAssertNil(navigation.popViewController(animated: false), "the root stays")
    }

    // MARK: - Back

    func testBackAsksFirstAndPopsOnlyOnApproval() {
        let (navigation, pages) = makeStack()
        var asked: [[UIViewController]] = []
        var approvals: [() -> Void] = []
        navigation.requestPop = { leaving, approve in
            asked.append(leaving)
            approvals.append(approve)
        }
        XCTAssertNil(navigation.popViewController(animated: false), "a deferred approval has no result yet")
        XCTAssertEqual(asked, [[pages[2]]])
        XCTAssertEqual(navigation.viewControllers.count, 3, "nothing moved")
        approvals[0]()
        XCTAssertEqual(navigation.viewControllers, [pages[0], pages[1]])
    }

    func testAnImmediateApprovalReturnsThePoppedController() {
        let (navigation, pages) = makeStack()
        navigation.requestPop = { _, approve in approve() }
        XCTAssertTrue(navigation.popViewController(animated: false) === pages[2])
        XCTAssertEqual(navigation.viewControllers.count, 2)
    }

    func testNeverApprovingKeepsThePageAndTheRootIsNotAsked() {
        let (navigation, pages) = makeStack()
        var asked = 0
        navigation.requestPop = { _, _ in asked += 1 }
        _ = navigation.popViewController(animated: false)
        XCTAssertEqual(navigation.viewControllers.count, 3)
        navigation.setViewControllers([pages[0]], animated: false)
        _ = navigation.popViewController(animated: false)
        XCTAssertEqual(asked, 1, "a root has no Back to admit")
    }

    func testARepeatedApprovalDoesNothing() {
        let (navigation, _) = makeStack()
        var approve: (() -> Void)?
        navigation.requestPop = { _, done in approve = done }
        _ = navigation.popViewController(animated: false)
        approve?()
        XCTAssertEqual(navigation.viewControllers.count, 2)
        approve?()
        XCTAssertEqual(navigation.viewControllers.count, 2, "the second call is ignored, it does not pop again")
    }

    func testAStaleApprovalAfterTheStackMovedOnIsIgnored() {
        let (navigation, pages) = makeStack()
        var approve: (() -> Void)?
        navigation.requestPop = { _, done in approve = done }
        _ = navigation.popViewController(animated: false)
        let other = UIViewController()
        navigation.pushViewController(other, animated: false)
        approve?()
        XCTAssertEqual(navigation.viewControllers, [pages[0], pages[1], pages[2], other], "the page asked about is no longer on top")
    }

    // MARK: - Ancestor menu and root

    func testPopToAnAncestorListsEveryPageThatWouldLeaveAndPopsOnApproval() {
        let (navigation, pages) = makeStack(4)
        var asked: [[UIViewController]] = []
        var approve: (() -> Void)?
        navigation.requestPop = { leaving, done in
            asked.append(leaving)
            approve = done
        }
        XCTAssertNil(navigation.popToViewController(pages[1], animated: false))
        XCTAssertEqual(asked, [[pages[2], pages[3]]])
        XCTAssertEqual(navigation.viewControllers.count, 4)
        approve?()
        XCTAssertEqual(navigation.viewControllers, [pages[0], pages[1]])
    }

    func testPopToTheTopOrAPageNotOnTheStackIsNotAsked() {
        let (navigation, pages) = makeStack()
        var asked = 0
        navigation.requestPop = { _, _ in asked += 1 }
        _ = navigation.popToViewController(pages[2], animated: false)
        _ = navigation.popToViewController(UIViewController(), animated: false)
        XCTAssertEqual(asked, 0)
        XCTAssertEqual(navigation.viewControllers.count, 3)
    }

    func testPopToRootIsAdmittedLikeAPopToTheFirstPage() {
        let (navigation, pages) = makeStack()
        var asked: [[UIViewController]] = []
        var approve: (() -> Void)?
        navigation.requestPop = { leaving, done in
            asked.append(leaving)
            approve = done
        }
        XCTAssertNil(navigation.popToRootViewController(animated: false))
        XCTAssertEqual(asked, [[pages[1], pages[2]]])
        approve?()
        XCTAssertEqual(navigation.viewControllers, [pages[0]])
    }

    func testAStaleApprovalToAPopToIsIgnoredWhenTheTargetIsGone() {
        let (navigation, pages) = makeStack(4)
        var approve: (() -> Void)?
        navigation.requestPop = { _, done in approve = done }
        _ = navigation.popToViewController(pages[1], animated: false)
        navigation.setViewControllers([pages[0], pages[2], pages[3]], animated: false)
        approve?()
        XCTAssertEqual(navigation.viewControllers.count, 3)
    }

    // MARK: - The swipe

    func testTheSystemEdgeSwipeBeginsOnlyWhereNoAdmissionIsRequired() throws {
        let (navigation, pages) = makeStack(show: true)
        let recognizer = try XCTUnwrap(navigation.interactivePopGestureRecognizer)
        XCTAssertTrue(recognizer.delegate === navigation)
        XCTAssertTrue(navigation.gestureRecognizerShouldBegin(recognizer), "no admission: UIKit's swipe works")
        navigation.requestPop = { _, _ in }
        XCTAssertFalse(navigation.gestureRecognizerShouldBegin(recognizer), "UIKit's swipe never calls popViewController, so it is kept off")
        navigation.requestPop = nil
        pages[2].navigationItem.hidesBackButton = true
        XCTAssertFalse(navigation.gestureRecognizerShouldBegin(recognizer), "a page without Back is not swiped from")
        navigation.setViewControllers([pages[0]], animated: false)
        XCTAssertFalse(navigation.gestureRecognizerShouldBegin(recognizer), "the root has nothing to pop to")
        XCTAssertTrue(navigation.gestureRecognizerShouldBegin(UITapGestureRecognizer()), "other recognizers are not ours to judge")
    }

    func testTheContentSwipeIsOffWhileAnAdmissionIsRequired() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26 content swipe") }
        let (navigation, _) = makeStack(show: true)
        let content = try XCTUnwrap(navigation.interactiveContentPopGestureRecognizer)
        navigation.requestPop = { _, _ in }
        XCTAssertFalse(content.isEnabled)
        navigation.requestPop = nil
        XCTAssertFalse(content.isEnabled, "it is only ever turned off here; the app or the motion turns it on")
    }

    func testTheStackMotionSwipeIsAdmittedThroughRequestPop() {
        let (navigation, pages) = makeStack(show: true)
        let motion = FentonStackMotion(navigation: navigation, reduceMotion: { false }, announceScreenChange: {})
        navigation.delegate = motion
        var asked: [[UIViewController]] = []
        var approve: (() -> Void)?
        navigation.requestPop = { leaving, done in
            asked.append(leaving)
            approve = done
        }
        motion.beginSwipe()
        XCTAssertEqual(asked, [[pages[2]]], "the swipe asks before the stack moves")
        XCTAssertEqual(navigation.viewControllers.count, 3)
        XCTAssertFalse(motion.isSwiping, "a deferred approval means no interactive pop is running")
        approve?()
        XCTAssertTrue(LaneBHost.spin(until: { navigation.viewControllers.count == 2 && navigation.transitionCoordinator == nil }))
    }

    func testTheStackMotionSwipeDeniedByTheAppLeavesThePage() {
        let (navigation, _) = makeStack(show: true)
        let motion = FentonStackMotion(navigation: navigation, reduceMotion: { false }, announceScreenChange: {})
        navigation.delegate = motion
        navigation.requestPop = { _, _ in }
        motion.beginSwipe()
        motion.updateSwipe(progress: 0.9)
        motion.endSwipe(progress: 0.9, velocity: 0)
        LaneBHost.spin(0.4)
        XCTAssertEqual(navigation.viewControllers.count, 3)
    }
}
#endif
