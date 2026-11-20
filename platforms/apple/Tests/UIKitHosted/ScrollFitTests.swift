#if os(iOS)
import FentonUIKit
import UIKit
import XCTest

@MainActor
final class ScrollFitTests: XCTestCase {
    func testAShortPageDoesNotBounceAndALongOneStillScrolls() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        scroll.alwaysBounceVertical = true
        FentonScrollFit.apply(to: scroll)
        scroll.contentSize = CGSize(width: 390, height: 300)
        XCTAssertFalse(scroll.alwaysBounceVertical, "content that fits neither bounces nor answers a drag")
        XCTAssertFalse(scroll.alwaysBounceHorizontal)
        XCTAssertFalse(scroll.showsHorizontalScrollIndicator)
        XCTAssertTrue(scroll.isDirectionalLockEnabled)
        scroll.contentSize = CGSize(width: 390, height: 3000)
        XCTAssertFalse(scroll.alwaysBounceVertical, "a long page scrolls because its content outgrows it, not because of the flag")
    }

    func testHorizontalOffsetIsRestoredAtOnce() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        scroll.contentSize = CGSize(width: 900, height: 3000)
        FentonScrollFit.apply(to: scroll)
        scroll.contentOffset = CGPoint(x: 120, y: 50)
        XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 0.01)
        XCTAssertEqual(scroll.contentOffset.y, 50, accuracy: 0.01, "only the horizontal axis is put back")
    }

    func testPinningTwiceKeepsOneObservation() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        scroll.contentSize = CGSize(width: 900, height: 3000)
        FentonScrollFit.pinWidth(of: scroll)
        FentonScrollFit.pinWidth(of: scroll)
        scroll.contentOffset.x = 40
        XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 0.01)
    }

    func testPullToRefreshIsTheException() {
        let scroll = UIScrollView()
        FentonScrollFit.apply(to: scroll)
        FentonScrollFit.allowsPullToRefresh(scroll)
        XCTAssertTrue(scroll.alwaysBounceVertical)
    }

    // MARK: - Locator

    func testLocatorPicksTheLargestVisibleScroller() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: root.frame)
        let controller = UIViewController()
        controller.view = root
        window.rootViewController = controller
        window.makeKeyAndVisible()

        let small = scroller(CGRect(x: 0, y: 0, width: 390, height: 150))
        let medium = scroller(CGRect(x: 0, y: 0, width: 390, height: 400))
        let large = scroller(CGRect(x: 0, y: 0, width: 390, height: 700))
        let hidden = scroller(CGRect(x: 0, y: 0, width: 390, height: 844))
        hidden.isHidden = true
        let fits = scroller(CGRect(x: 0, y: 0, width: 390, height: 844), contentHeight: 100)
        let offscreen = scroller(CGRect(x: 0, y: 2000, width: 390, height: 800))
        for view in [small, medium, offscreen, fits, hidden, large] { root.addSubview(view) }
        XCTAssertTrue(FentonScrollLocator.mainScrollView(in: root) === large)
        large.alpha = 0
        XCTAssertTrue(FentonScrollLocator.mainScrollView(in: root) === medium)
        XCTAssertNil(FentonScrollLocator.mainScrollView(in: UIView()), "not in a window")
    }

    private func scroller(_ frame: CGRect, contentHeight: CGFloat = 5000) -> UIScrollView {
        let scroll = UIScrollView(frame: frame)
        scroll.contentSize = CGSize(width: frame.width, height: contentHeight)
        return scroll
    }
}
#endif
