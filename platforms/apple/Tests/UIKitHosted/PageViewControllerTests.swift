#if os(iOS)
import FentonAppleCore
import FentonAppleTelemetry
import FentonUIKit
import UIKit
import XCTest

/// A scroll view that reports a drag in progress, which a test cannot start with a real touch.
private final class DraggingScrollView: UIScrollView {
    override var isDragging: Bool { true }
}

private final class WriteCounter: @unchecked Sendable { var count = 0 }

/// A page whose bar items the test changes.
@MainActor
private final class ChromePage: FentonPageViewController {
    var leading: [UIBarButtonItem] = []
    var trailing: [UIBarButtonItem] = []
    override func barItems() -> FentonBarItems { FentonBarItems(leading: leading, trailing: trailing) }
}

@MainActor
final class PageViewControllerTests: XCTestCase {
    private var environment = FentonWindowEnvironment()

    override func setUp() async throws {
        environment = FentonWindowEnvironment()
    }

    private func makePage(_ configuration: FentonPageConfiguration = .init(), title: String? = "Page") -> FentonPageViewController {
        FentonPageViewController(environment: environment, configuration: configuration, title: title)
    }

    /// A page in a navigation controller in a window, laid out.
    private func hostedPage(_ page: FentonPageViewController) -> (UIWindow, UINavigationController) {
        let navigation = UINavigationController(rootViewController: page)
        navigation.navigationBar.prefersLargeTitles = true
        let window = pageTestWindow(navigation)
        pageTurnRunLoop(2)
        return (window, navigation)
    }

    // MARK: - Side insets

    func testContentViewIsInsetOnlyByTheGeometricSideInsets() {
        let page = makePage()
        page.sideInsetsOverride = UIEdgeInsets(top: 30, left: 0, bottom: 20, right: 40)
        let window = pageTestWindow(page)
        pageTurnRunLoop(2)
        withExtendedLifetime(window) {
            XCTAssertEqual(page.contentView.frame, CGRect(x: 0, y: 0, width: 350, height: 844),
                           "full height (top and bottom ignored), inset at the trailing side only")
        }
        page.sideInsetsOverride = nil
        page.view.layoutIfNeeded()
        XCTAssertEqual(page.contentView.frame.width, 390, "no rail: full width")
    }

    func testChildrenAbsorbTheSideInsetsSoTheyAreNotInsetTwice() {
        let page = makePage()
        page.sideInsetsOverride = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 40)
        let child = UIViewController()
        page.addChild(child)
        page.contentView.addSubview(child.view)
        child.didMove(toParent: page)
        let window = pageTestWindow(page)
        pageTurnRunLoop(2)
        withExtendedLifetime(window) {
            XCTAssertEqual(child.additionalSafeAreaInsets.left, -12)
            XCTAssertEqual(child.additionalSafeAreaInsets.right, -40)
            XCTAssertEqual(page.additionalSafeAreaInsets.right, 40, "the page's own side safe area is the geometric one")
        }
    }

    // MARK: - Layout settles

    func testASecondIdenticalLayoutWritesNothing() {
        let page = makePage()
        page.sideInsetsOverride = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 40)
        let window = pageTestWindow(page)
        pageTurnRunLoop(2)
        let frame = page.contentView.frame
        let additional = page.additionalSafeAreaInsets
        let counter = PageLayoutCounter.install(on: page.view)
        pageTurnRunLoop(2, seconds: 0.25)
        withExtendedLifetime(window) {
            XCTAssertEqual(counter.count, 0, "an idle page runs no layout pass over two run-loop turns")
            page.view.setNeedsLayout()
            page.view.layoutIfNeeded()
            XCTAssertEqual(counter.count, 1, "a requested layout runs once and does not ask for another")
            pageTurnRunLoop(2, seconds: 0.25)
            XCTAssertEqual(counter.count, 1)
            XCTAssertEqual(page.contentView.frame, frame)
            XCTAssertEqual(page.additionalSafeAreaInsets, additional)
        }
    }

    func testAPageWithAScrollViewAndAccessorySettlesToo() {
        let page = makePage()
        let scroll = UIScrollView()
        scroll.contentSize = CGSize(width: 390, height: 3000)
        page.loadViewIfNeeded()
        page.install(scrollView: scroll)
        let label = UILabel()
        label.text = "Status"
        page.bottomAccessory = label
        let (window, _) = hostedPage(page)
        let counter = PageLayoutCounter.install(on: page.view)
        pageTurnRunLoop(2, seconds: 0.25)
        withExtendedLifetime(window) { XCTAssertEqual(counter.count, 0) }
    }

    /// The regression the research note asked for: `FentonPageContainerViewController.viewDidLayoutSubviews` calls
    /// `containmentView.setNeedsLayout()` on its own view. This records, for the old container and the new page, how many
    /// `layoutSubviews` passes the page's own view runs while idle over two run-loop turns, and how many one requested layout
    /// costs once it settles. Only the new page is asserted: the old container is documented, not gated on (its figures are
    /// attached to the test and printed as `LAYOUTPASSES`).
    func testLayoutPassCountOfTheOldContainerIsRecordedAndTheNewPageSettles() {
        func measure(_ controller: UIViewController) -> (idle: Int, requested: Int) {
            let window = pageTestWindow(controller)
            pageTurnRunLoop(2, seconds: 0.25)
            let counter = PageLayoutCounter.install(on: controller.view)
            pageTurnRunLoop(2, seconds: 0.25)
            let idle = counter.count
            controller.view.setNeedsLayout()
            pageTurnRunLoop(2, seconds: 0.25)
            let requested = counter.count - idle
            window.isHidden = true
            return (idle, requested)
        }
        let old = FentonPageContainerViewController()
        old.embed(UIViewController(), mainScrollView: UIScrollView())
        let oldPasses = measure(old)

        let page = makePage()
        page.install(scrollView: UIScrollView())
        let newPasses = measure(page)

        let note = "layoutSubviews passes of the page's own view over two 0.25 s run-loop turns (idle, then after one setNeedsLayout): FentonPageContainerViewController idle=\(oldPasses.idle) requested=\(oldPasses.requested); FentonPageViewController idle=\(newPasses.idle) requested=\(newPasses.requested)"
        print("LAYOUTPASSES \(note)")
        let attachment = XCTAttachment(string: note)
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(newPasses.idle, 0, note)
        XCTAssertEqual(newPasses.requested, 1, note)
    }

    // MARK: - Scroll view ownership

    func testInstallLeavesInsetsToTheSystemAndNamesTheScrollViewForTheBar() {
        let page = makePage()
        let scroll = UIScrollView()
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.alwaysBounceVertical = true
        page.loadViewIfNeeded()
        page.install(scrollView: scroll)
        XCTAssertEqual(scroll.contentInsetAdjustmentBehavior, .automatic)
        XCTAssertTrue(page.contentScrollView(for: .top) === scroll)
        XCTAssertTrue(page.contentScrollView === scroll)
        XCTAssertTrue(scroll.superview === page.contentView)
        XCTAssertFalse(scroll.alwaysBounceVertical, "scrolls only when content outgrows it")
        XCTAssertEqual(scroll.backgroundColor, .clear)
        let (window, _) = hostedPage(page)
        withExtendedLifetime(window) {
            XCTAssertEqual(scroll.contentInset, .zero, "the page never writes the scroll view's inset")
            XCTAssertGreaterThan(scroll.adjustedContentInset.top, 0, "the system added the bar")
        }
        page.setPageScrollView(nil)
        XCTAssertNil(page.contentScrollView)
        XCTAssertNil(page.contentScrollView(for: .top))
    }

    /// Grows the bar above `scroll` by 40 points (through the page's safe area) and returns how many times the page moved the offset,
    /// and where the offset ended. UIKit also moves a resting offset itself on most inset changes, so the counter, not the final
    /// offset, tells the page's own follow apart.
    private func growTheBar(over scroll: UIScrollView, offset: CGFloat?) -> (moves: Int, finalOffset: CGFloat, inset: CGFloat) {
        let telemetry = FentonTelemetry(enabled: true)
        let page = FentonPageViewController(environment: environment, telemetry: telemetry, title: "Page")
        scroll.contentSize = CGSize(width: 390, height: 4000)
        page.loadViewIfNeeded()
        page.install(scrollView: scroll)
        let (window, _) = hostedPage(page)
        defer { window.isHidden = true }
        pageTurnRunLoop(3, seconds: 0.2)
        scroll.contentOffset.y = offset ?? -scroll.adjustedContentInset.top
        page.view.layoutIfNeeded()
        pageTurnRunLoop(3, seconds: 0.2)
        // The first layouts may move it as the large title arrives; only what the growth does is counted.
        let before = telemetry.snapshot().counters["page.follow-top.move"] ?? 0
        page.additionalSafeAreaInsets.top += 40
        page.view.layoutIfNeeded()
        pageTurnRunLoop(2, seconds: 0.2)
        return ((telemetry.snapshot().counters["page.follow-top.move"] ?? 0) - before, scroll.contentOffset.y, scroll.adjustedContentInset.top)
    }

    func testFollowTopInsetMovesARestingScrollView() {
        let result = growTheBar(over: UIScrollView(), offset: nil)
        XCTAssertEqual(result.moves, 1, "a page at rest is moved to its new top once")
        XCTAssertEqual(result.finalOffset, -result.inset, accuracy: 0.5)
    }

    func testFollowTopInsetNeverMovesADraggingScrollView() {
        let result = growTheBar(over: DraggingScrollView(), offset: nil)
        XCTAssertEqual(result.moves, 0, "a drag is never moved")
    }

    func testFollowTopInsetLeavesAScrolledPageAlone() {
        let result = growTheBar(over: UIScrollView(), offset: 500)
        XCTAssertEqual(result.moves, 0, "a page nobody left at its top is not pulled back")
    }

    // MARK: - Bottom accessory

    func testAccessoryAddsToTheBottomSafeAreaOnceAndRemovesIt() {
        let page = makePage()
        let label = UILabel()
        label.text = "Status"
        label.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let window = pageTestWindow(page)
        page.bottomAccessory = label
        pageTurnRunLoop(2)
        withExtendedLifetime(window) {
            let added = page.additionalSafeAreaInsets.bottom
            XCTAssertGreaterThanOrEqual(added, 30, "the bar's height joined the safe area")
            XCTAssertLessThan(added, 120)
            for _ in 0..<3 { page.view.setNeedsLayout(); page.view.layoutIfNeeded() }
            XCTAssertEqual(page.additionalSafeAreaInsets.bottom, added, "added once, not once per layout")
            page.bottomAccessory = nil
            pageTurnRunLoop(1)
            XCTAssertEqual(page.additionalSafeAreaInsets.bottom, 0)
            XCTAssertNil(label.superview?.superview, "the bar is out of the page")
        }
    }

    func testReplacingTheAccessoryDoesNotStackTheInset() {
        let page = makePage()
        let first = UILabel(), second = UILabel()
        first.heightAnchor.constraint(equalToConstant: 30).isActive = true
        second.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let window = pageTestWindow(page)
        page.bottomAccessory = first
        pageTurnRunLoop(2)
        let once = page.additionalSafeAreaInsets.bottom
        page.bottomAccessory = second
        pageTurnRunLoop(2)
        withExtendedLifetime(window) {
            XCTAssertEqual(page.additionalSafeAreaInsets.bottom, once)
            XCTAssertNil(first.superview?.superview)
        }
    }

    // MARK: - Chrome seam and title

    func testBarItemsSeamWritesOnlyWhenTheAnswerChanged() {
        let page = ChromePage(environment: environment, title: "Chrome")
        let (window, _) = hostedPage(page)
        withExtendedLifetime(window) {
            XCTAssertNil(page.navigationItem.rightBarButtonItems, "default: no chrome")
            let counter = WriteCounter()
            let token = page.navigationItem.observe(\.rightBarButtonItems) { _, _ in counter.count += 1 }
            let item = UIBarButtonItem(title: "Act", style: .plain, target: nil, action: nil)
            page.trailing = [item]
            page.leading = [UIBarButtonItem(title: "Lead", style: .plain, target: nil, action: nil)]
            page.chromeChanged()
            XCTAssertEqual(page.navigationItem.rightBarButtonItems?.count, 1)
            XCTAssertEqual(page.navigationItem.leftBarButtonItems?.count, 1)
            XCTAssertEqual(counter.count, 1)
            page.chromeChanged()
            page.chromeChanged()
            XCTAssertEqual(counter.count, 1, "the same items on the bar write nothing")
            page.trailing = []
            page.chromeChanged()
            XCTAssertNil(page.navigationItem.rightBarButtonItems)
            token.invalidate()
        }
    }

    func testTitleStylesSetTheLargeTitleMode() {
        let large = makePage(.init())
        let inline = makePage({ var c = FentonPageConfiguration(); c.titleStyle = .inline; return c }())
        let sheet = makePage({ var c = FentonPageConfiguration(); c.surface = .sheet; return c }())
        for page in [large, inline, sheet] { page.loadViewIfNeeded() }
        pageTurnRunLoop(1)
        XCTAssertEqual(large.navigationItem.largeTitleDisplayMode, .automatic)
        XCTAssertEqual(inline.navigationItem.largeTitleDisplayMode, .never)
        XCTAssertEqual(sheet.navigationItem.largeTitleDisplayMode, .never)
        XCTAssertEqual(large.navigationItem.backButtonDisplayMode, .minimal)
        XCTAssertEqual(sheet.view.backgroundColor, .systemGroupedBackground)
        XCTAssertEqual(large.view.backgroundColor, .clear)
    }

    func testFixedInlineStyleWritesTheFixedTitleOnce() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("the attributed bar title is iOS 26 and later") }
        var configuration = FentonPageConfiguration()
        configuration.titleStyle = .fixedInline
        let page = makePage(configuration, title: "Rail")
        let (window, _) = hostedPage(page)
        withExtendedLifetime(window) {
            let attributed = page.navigationItem.attributedTitle
            XCTAssertEqual(attributed.map { String($0.characters) }, "Rail")
            XCTAssertEqual(page.navigationItem.largeTitleDisplayMode, .never)
        }
    }

    func testHeaderCapFollowsTheEnvironmentWithoutALayoutLoop() {
        let page = makePage()
        let window = pageTestWindow(page)
        pageTurnRunLoop(2)
        let counter = PageLayoutCounter.install(on: page.view)
        environment.headerEdgeCap = 96
        pageTurnRunLoop(2, seconds: 0.25)
        withExtendedLifetime(window) { XCTAssertLessThanOrEqual(counter.count, 1) }
    }

    func testFirstLayoutIsMeasuredOnce() {
        let telemetry = FentonTelemetry(enabled: true)
        let page = FentonPageViewController(environment: environment, telemetry: telemetry, title: "T")
        let window = pageTestWindow(page)
        pageTurnRunLoop(2)
        page.view.setNeedsLayout()
        page.view.layoutIfNeeded()
        withExtendedLifetime(window) {
            XCTAssertEqual(telemetry.snapshot().samples.filter { $0.name == "page.first-layout" }.count, 1)
        }
    }

    // MARK: - Scroll to top

    func testScrollToTopReturnsToTheRestingOffset() {
        let page = makePage()
        let scroll = UIScrollView()
        scroll.contentSize = CGSize(width: 390, height: 4000)
        page.loadViewIfNeeded()
        page.install(scrollView: scroll)
        let (window, _) = hostedPage(page)
        scroll.contentOffset.y = 800
        page.scrollToTop(animated: false)
        withExtendedLifetime(window) { XCTAssertEqual(scroll.contentOffset.y, -scroll.adjustedContentInset.top, accuracy: 0.5) }
    }
}
#endif
