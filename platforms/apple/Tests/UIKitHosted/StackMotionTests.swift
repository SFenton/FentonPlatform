#if os(iOS)
import FentonAppleCore
@testable import FentonUIKit
import UIKit
import XCTest

@MainActor
final class StackMotionTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    private struct Rig {
        let navigation: FentonNavigationController
        let motion: FentonStackMotion
        let root: UIViewController
        let announcements: Counter
    }

    @MainActor
    final class Counter {
        var count = 0
    }

    private func makeRig(reduceMotion: Bool = false, enabled: @escaping () -> Bool = { true },
                         motion spring: FentonMotion = FentonMotion()) -> Rig {
        let root = UIViewController()
        root.view.backgroundColor = .systemBackground
        let navigation = FentonNavigationController(rootViewController: root)
        navigation.isNavigationBarHidden = true
        windows.append(pageTestWindow(navigation))
        let counter = Counter()
        let motion = FentonStackMotion(navigation: navigation, motion: spring, reduceMotion: { reduceMotion }, isEnabled: enabled,
                                       announceScreenChange: { counter.count += 1 })
        navigation.delegate = motion
        return Rig(navigation: navigation, motion: motion, root: root, announcements: counter)
    }

    private func pushed(_ rig: Rig, animated: Bool = false) -> UIViewController {
        let page = UIViewController()
        page.view.backgroundColor = .systemBackground
        rig.navigation.pushViewController(page, animated: animated)
        return page
    }

    private func settle(_ rig: Rig) {
        XCTAssertTrue(LaneBHost.spin(until: { rig.navigation.transitionCoordinator == nil }))
        LaneBHost.spin(0.05)
    }

    // MARK: - Completion rule

    func testCompletesTable() {
        let table: [(CGFloat, CGFloat, Bool)] = [
            (0.0, 0, false), (0.3, 0, false), (0.5, 0, false), (0.51, 0, true), (1.0, 0, true),
            (0.1, 600, false), (0.1, 601, true), (0.1, 2000, true), (0.4, -900, false), (0.6, -900, true)
        ]
        for (progress, velocity, expected) in table {
            XCTAssertEqual(FentonStackMotion.completes(progress: progress, velocity: velocity), expected, "progress \(progress) velocity \(velocity)")
        }
        XCTAssertEqual(FentonStackMotion.completionFraction, 0.5)
        XCTAssertEqual(FentonStackMotion.completionVelocity, 600)
    }

    // MARK: - Animation controller

    func testPushAndPopGetTheStackTransitionAndNoneGetsNothing() {
        let rig = makeRig()
        let page = pushed(rig)
        let push = rig.motion.navigationController(rig.navigation, animationControllerFor: .push, from: rig.root, to: page)
        let pop = rig.motion.navigationController(rig.navigation, animationControllerFor: .pop, from: page, to: rig.root)
        XCTAssertEqual((push as? FentonStackTransition)?.isPush, true)
        XCTAssertEqual((pop as? FentonStackTransition)?.isPush, false)
        XCTAssertNil(rig.motion.navigationController(rig.navigation, animationControllerFor: .none, from: rig.root, to: page))
    }

    func testADisabledMotionReturnsNothingAndTheSwipeDoesNotBegin() {
        var enabled = false
        let rig = makeRig(enabled: { enabled })
        let page = pushed(rig)
        XCTAssertNil(rig.motion.navigationController(rig.navigation, animationControllerFor: .push, from: rig.root, to: page))
        XCTAssertFalse(rig.motion.gestureRecognizerShouldBegin(rig.motion.edgePanRecognizer))
        enabled = true
        XCTAssertTrue(rig.motion.gestureRecognizerShouldBegin(rig.motion.edgePanRecognizer))
    }

    func testTheTransitionRunsOnTheMotionsSpringOrTheQuickFadeUnderReduceMotion() {
        let motion = FentonMotion(standard: .init(duration: 0.42, bounce: 0), quick: 0.11, crossFade: 0.2)
        XCTAssertEqual(FentonStackTransition(isPush: true, reduceMotion: false, motion: motion).duration, 0.42)
        XCTAssertEqual(FentonStackTransition(isPush: true, reduceMotion: true, motion: motion).duration, 0.11)
        XCTAssertEqual(FentonStackTransition(isPush: true, reduceMotion: false, motion: motion)
            .transitionDuration(using: nil), 0.42)
    }

    func testTheInteractionControllerIsHandedOnlyToOurTransitionAndOnlyDuringASwipe() {
        let rig = makeRig()
        let page = pushed(rig)
        let transition = FentonStackTransition(isPush: false, reduceMotion: false)
        XCTAssertNil(rig.motion.navigationController(rig.navigation, interactionControllerFor: transition), "no swipe, no interaction")
        rig.motion.beginSwipe()
        XCTAssertTrue(rig.motion.isSwiping)
        LaneBHost.spin(0.05)
        XCTAssertNotNil(rig.motion.navigationController(rig.navigation, interactionControllerFor: transition))
        class Other: NSObject, UIViewControllerAnimatedTransitioning {
            func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval { 0 }
            func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {}
        }
        XCTAssertNil(rig.motion.navigationController(rig.navigation, interactionControllerFor: Other()))
        rig.motion.endSwipe(progress: 0, velocity: 0, cancelled: true)
        settle(rig)
        XCTAssertEqual(rig.navigation.viewControllers.last, page)
    }

    // MARK: - Real transitions

    func testAnAnimatedPushSlidesTheNewPageInFromTheTrailingEdge() throws {
        let rig = makeRig()
        let page = pushed(rig, animated: true)
        let coordinator = try XCTUnwrap(rig.navigation.transitionCoordinator)
        let to = try XCTUnwrap(coordinator.view(forKey: .to))
        LaneBHost.spin(0.03)
        // The model values are the destination; the presentation layer shows where the animation is.
        let shown = try XCTUnwrap(to.layer.presentation())
        XCTAssertGreaterThan(shown.affineTransform().tx, 100, "the new page starts a width away")
        XCTAssertEqual(shown.opacity, 1, "no fade")
        settle(rig)
        XCTAssertEqual(to.transform, .identity)
        XCTAssertEqual(page.view.alpha, 1)
        XCTAssertEqual(rig.root.view.transform, .identity, "the page that left is put back")
    }

    func testReduceMotionIsACrossFadeWithNoSlide() throws {
        let rig = makeRig(reduceMotion: true)
        _ = pushed(rig, animated: true)
        let coordinator = try XCTUnwrap(rig.navigation.transitionCoordinator)
        let to = try XCTUnwrap(coordinator.view(forKey: .to))
        LaneBHost.spin(0.03)
        let shown = try XCTUnwrap(to.layer.presentation())
        XCTAssertEqual(shown.affineTransform().tx, 0, accuracy: 0.5, "nothing slides")
        XCTAssertLessThan(shown.opacity, 1, "the new page fades in")
        settle(rig)
        XCTAssertEqual(to.alpha, 1)
    }

    func testAnimatedPushAndPopTellVoiceOverTheScreenChangedButAnUnanimatedOneDoesNot() {
        let rig = makeRig()
        _ = pushed(rig, animated: false)
        settle(rig)
        XCTAssertEqual(rig.announcements.count, 0)
        _ = pushed(rig, animated: true)
        settle(rig)
        XCTAssertEqual(rig.announcements.count, 1)
        rig.navigation.popViewController(animated: true)
        settle(rig)
        XCTAssertEqual(rig.announcements.count, 2)
    }

    func testAMotionThatIsDisabledDoesNotAnnounce() {
        let rig = makeRig(enabled: { false })
        _ = pushed(rig, animated: true)
        settle(rig)
        XCTAssertEqual(rig.announcements.count, 0)
    }

    func testTheSystemRecognisersAreOffAfterEveryTransition() throws {
        let rig = makeRig()
        let system = try XCTUnwrap(rig.navigation.interactivePopGestureRecognizer)
        XCTAssertFalse(system.isEnabled)
        _ = pushed(rig, animated: true)
        settle(rig)
        XCTAssertFalse(system.isEnabled)
        system.isEnabled = true
        rig.motion.navigationController(rig.navigation, didShow: rig.root, animated: false)
        XCTAssertFalse(system.isEnabled, "UIKit turns it back on when the stack changes; didShow turns it off")
        if #available(iOS 26.0, *) {
            let content = try XCTUnwrap(rig.navigation.interactiveContentPopGestureRecognizer)
            XCTAssertFalse(content.isEnabled)
        }
    }

    func testAnAnimatedPopReturnsThePagesToPlace() {
        let rig = makeRig()
        let page = pushed(rig)
        rig.navigation.popViewController(animated: true)
        settle(rig)
        XCTAssertEqual(rig.navigation.viewControllers, [rig.root])
        XCTAssertEqual(rig.root.view.transform, .identity)
        XCTAssertEqual(rig.root.view.alpha, 1)
        XCTAssertNil(page.parent)
    }

    // MARK: - The edge pan

    func testTheEdgePanSitsOnTheStacksViewAtTheLeadingEdge() {
        let rig = makeRig()
        let pan = rig.motion.edgePanRecognizer
        XCTAssertTrue(rig.navigation.view.gestureRecognizers?.contains(pan) == true)
        XCTAssertEqual(pan.edges, .left)
        XCTAssertTrue(pan.delegate === rig.motion)
        XCTAssertEqual(pan.name, "FentonStackMotion.edgePan")
    }

    func testTheSwipeBeginsOnlyWithAPageToPopTo() {
        let rig = makeRig()
        XCTAssertFalse(rig.motion.gestureRecognizerShouldBegin(rig.motion.edgePanRecognizer), "the root has no Back")
        let page = pushed(rig)
        XCTAssertTrue(rig.motion.gestureRecognizerShouldBegin(rig.motion.edgePanRecognizer))
        page.navigationItem.hidesBackButton = true
        XCTAssertFalse(rig.motion.gestureRecognizerShouldBegin(rig.motion.edgePanRecognizer), "a page that hides Back is not swiped from")
        XCTAssertFalse(rig.motion.gestureRecognizerShouldBegin(UITapGestureRecognizer()), "only our own pan")
    }

    func testOnlyAnEdgePanOutsideTheStackRunsAlongsideAndScrollViewsWaitForTheSwipe() {
        let rig = makeRig()
        let outside = UIScreenEdgePanGestureRecognizer()
        let outsideView = UIView()
        outsideView.addGestureRecognizer(outside)
        XCTAssertTrue(rig.motion.gestureRecognizer(rig.motion.edgePanRecognizer, shouldRecognizeSimultaneouslyWith: outside))
        let inside = UIScreenEdgePanGestureRecognizer()
        rig.root.view.addGestureRecognizer(inside)
        XCTAssertFalse(rig.motion.gestureRecognizer(rig.motion.edgePanRecognizer, shouldRecognizeSimultaneouslyWith: inside), "the columns' pan never does")
        XCTAssertFalse(rig.motion.gestureRecognizer(rig.motion.edgePanRecognizer, shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer()))

        let scroll = UIScrollView()
        rig.root.view.addSubview(scroll)
        XCTAssertTrue(rig.motion.gestureRecognizer(rig.motion.edgePanRecognizer, shouldBeRequiredToFailBy: scroll.panGestureRecognizer))
        let foreign = UIScrollView()
        XCTAssertFalse(rig.motion.gestureRecognizer(rig.motion.edgePanRecognizer, shouldBeRequiredToFailBy: foreign.panGestureRecognizer))
        XCTAssertFalse(rig.motion.gestureRecognizer(rig.motion.edgePanRecognizer, shouldBeRequiredToFailBy: UITapGestureRecognizer()))
    }

    func testASwipePastHalfPopsAndAShortOneReverses() {
        let rig = makeRig()
        let page = pushed(rig)
        rig.motion.beginSwipe()
        XCTAssertTrue(rig.motion.isSwiping)
        LaneBHost.spin(0.05)
        rig.motion.beginSwipe()
        rig.motion.updateSwipe(progress: 0.2)
        rig.motion.endSwipe(progress: 0.2, velocity: 0)
        XCTAssertFalse(rig.motion.isSwiping)
        settle(rig)
        XCTAssertEqual(rig.navigation.viewControllers.last, page, "a short slow drag reverses")

        rig.motion.beginSwipe()
        LaneBHost.spin(0.05)
        rig.motion.updateSwipe(progress: 5)
        rig.motion.updateSwipe(progress: -1)
        rig.motion.updateSwipe(progress: 0.8)
        rig.motion.endSwipe(progress: 0.8, velocity: 0)
        settle(rig)
        XCTAssertEqual(rig.navigation.viewControllers, [rig.root], "past halfway completes")
        rig.motion.endSwipe(progress: 1, velocity: 0)
        rig.motion.updateSwipe(progress: 1)
    }

    func testAFlickPopsAndACancelledSwipeReverses() {
        let rig = makeRig()
        let page = pushed(rig)
        rig.motion.beginSwipe()
        LaneBHost.spin(0.05)
        rig.motion.endSwipe(progress: 0.1, velocity: 900)
        settle(rig)
        XCTAssertEqual(rig.navigation.viewControllers, [rig.root])
        rig.navigation.pushViewController(page, animated: false)
        rig.motion.beginSwipe()
        LaneBHost.spin(0.05)
        rig.motion.updateSwipe(progress: 0.9)
        rig.motion.endSwipe(progress: 0.9, velocity: 900, cancelled: true)
        settle(rig)
        XCTAssertEqual(rig.navigation.viewControllers.last, page)
    }

    func testTheSwipeDoesNothingAtTheRoot() {
        let rig = makeRig()
        rig.motion.beginSwipe()
        XCTAssertFalse(rig.motion.isSwiping)
    }
}
#endif
