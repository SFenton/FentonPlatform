#if os(iOS)
import FentonAppleCore
import FentonUIKit
import UIKit
import XCTest

@MainActor
private final class StyledChild: UIViewController {
    var style = UIStatusBarStyle.lightContent
    override var preferredStatusBarStyle: UIStatusBarStyle { style }
}

@MainActor
final class PageHostTests: XCTestCase {
    private let environment = FentonWindowEnvironment()

    func testWrappedReturnsPagesAndNavigationControllersUnchanged() {
        let page = FentonPageViewController(environment: environment)
        let navigation = UINavigationController(rootViewController: UIViewController())
        let host = FentonPageHost(child: UIViewController(), environment: environment)
        XCTAssertTrue(FentonPageHost.wrapped(page, environment: environment) === page)
        XCTAssertTrue(FentonPageHost.wrapped(navigation, environment: environment) === navigation)
        XCTAssertTrue(FentonPageHost.wrapped(host, environment: environment) === host, "a host is a page")
    }

    func testWrappedHostsAPlainControllerInTheContentView() {
        let plain = UIViewController()
        plain.title = "Plain"
        let wrapped = FentonPageHost.wrapped(plain, environment: environment)
        let host = wrapped as? FentonPageHost
        XCTAssertNotNil(host)
        wrapped.loadViewIfNeeded()
        XCTAssertTrue(plain.parent === wrapped)
        XCTAssertTrue(plain.view.superview === host?.contentView)
        XCTAssertEqual(wrapped.title, "Plain")
    }

    func testTheHostLinksTheLargestScrollerOnceItIsOnScreen() {
        let child = UIViewController()
        let scroll = UIScrollView()
        scroll.contentSize = CGSize(width: 390, height: 4000)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        child.loadViewIfNeeded()
        child.view.addSubview(scroll)
        FentonEmbedding.pin(scroll, to: child.view)
        let host = FentonPageHost(child: child, environment: environment)
        let navigation = UINavigationController(rootViewController: host)
        let window = pageTestWindow(navigation)
        pageTurnRunLoop(2)
        withExtendedLifetime(window) {
            XCTAssertTrue(host.contentScrollView === scroll)
            XCTAssertEqual(scroll.contentInsetAdjustmentBehavior, .automatic)
            XCTAssertTrue(host.contentScrollView(for: .top) === scroll)
        }
    }

    func testASheetHostLeavesTheScrollViewAloneAndMirrorsTheChromeOfTheChild() {
        let child = UIViewController()
        child.title = "Form"
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.contentSize = CGSize(width: 390, height: 4000)
        child.loadViewIfNeeded()
        child.view.addSubview(scroll)
        scroll.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        var configuration = FentonPageConfiguration()
        configuration.surface = .sheet
        let host = FentonPageHost(child: child, environment: environment, linksScroll: false, configuration: configuration)
        let navigation = UINavigationController(rootViewController: host)
        let window = pageTestWindow(navigation)
        pageTurnRunLoop(2)
        withExtendedLifetime(window) {
            XCTAssertNil(host.contentScrollView)
            XCTAssertTrue(scroll.alwaysBounceVertical, "scrolls and bounces as it did")
            XCTAssertEqual(host.navigationItem.title, "Form")
            let done = UIBarButtonItem(title: "Done", style: .done, target: nil, action: nil)
            child.navigationItem.rightBarButtonItems = [done]
            XCTAssertTrue(host.navigationItem.rightBarButtonItems?.first === done)
            child.navigationItem.title = "Renamed"
            XCTAssertEqual(host.navigationItem.title, "Renamed")
        }
    }

    func testTheHostForwardsTheChildsStatusBarStyle() {
        let child = StyledChild()
        let host = FentonPageHost(child: child, environment: environment)
        host.loadViewIfNeeded()
        XCTAssertTrue(host.childForStatusBarStyle === child)
        XCTAssertTrue(host.childForStatusBarHidden === child)
        XCTAssertEqual(host.preferredStatusBarStyle, .default, "the host reads the child through childForStatusBarStyle")
    }

    // MARK: - FentonEmbedding

    func testEmbedAddsPinsAndIsIdempotent() {
        let parent = UIViewController()
        let child = UIViewController()
        parent.loadViewIfNeeded()
        FentonEmbedding.embed(child, in: parent)
        FentonEmbedding.embed(child, in: parent)
        XCTAssertTrue(child.parent === parent)
        XCTAssertEqual(parent.children.count, 1)
        XCTAssertEqual(parent.view.subviews.filter { $0 === child.view }.count, 1)
        XCTAssertEqual(parent.view.constraints.filter { $0.firstItem === child.view || $0.secondItem === child.view }.count, 4)
        parent.view.frame = CGRect(x: 0, y: 0, width: 200, height: 300)
        parent.view.layoutIfNeeded()
        XCTAssertEqual(child.view.frame, parent.view.bounds)
    }

    func testEmbedInAContainerWithInsetsAndRemove() {
        let parent = UIViewController()
        let child = UIViewController()
        parent.loadViewIfNeeded()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
        parent.view.addSubview(container)
        FentonEmbedding.embed(child, in: parent, container: container, insets: UIEdgeInsets(top: 10, left: 5, bottom: 20, right: 15))
        container.layoutIfNeeded()
        XCTAssertEqual(child.view.frame, CGRect(x: 5, y: 10, width: 180, height: 270))
        FentonEmbedding.remove(child)
        XCTAssertNil(child.parent)
        XCTAssertNil(child.view.superview)
        FentonEmbedding.remove(child)
    }

    func testEmbedMovesAChildFromAnotherParent() {
        let first = UIViewController(), second = UIViewController(), child = UIViewController()
        first.loadViewIfNeeded()
        second.loadViewIfNeeded()
        FentonEmbedding.embed(child, in: first)
        FentonEmbedding.embed(child, in: second)
        XCTAssertTrue(child.parent === second)
        XCTAssertTrue(first.children.isEmpty)
    }
}
#endif
