#if os(iOS)
import FentonAppleCore
@testable import FentonUIKit
import UIKit
import XCTest

/// The page base reacting to the window's facts, driven the way the app drives them: a `FentonWindowSignals` with injected
/// `FentonWindowSensors` (a `FakeDuo`) writes the environment, and the page follows. The setters of the environment stay closed.
@MainActor
final class PageEnvironmentTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    private struct Rig {
        let page: FentonPageViewController
        let navigation: UINavigationController
        let environment: FentonWindowEnvironment
        let duo: FakeDuo
        let signals: FentonWindowSignals
    }

    private func makeRig(configuration: FentonPageConfiguration = FentonPageConfiguration(), withScroll: Bool = false) -> Rig {
        let environment = FentonWindowEnvironment()
        let duo = FakeDuo()
        let page = FentonPageViewController(environment: environment, configuration: configuration, title: "Rail")
        if withScroll {
            let scroll = UIScrollView()
            scroll.contentSize = CGSize(width: 390, height: 4000)
            page.loadViewIfNeeded()
            page.install(scrollView: scroll)
        }
        let navigation = UINavigationController(rootViewController: page)
        navigation.navigationBar.prefersLargeTitles = true
        windows.append(pageTestWindow(navigation))
        let signals = FentonWindowSignals(view: page.view, environment: environment, presence: FentonHingePresence(),
                                          sensors: duo.sensors, reflow: nil)
        signals.refresh()
        pageTurnRunLoop(2)
        return Rig(page: page, navigation: navigation, environment: environment, duo: duo, signals: signals)
    }

    private func update(_ rig: Rig) {
        rig.signals.refresh()
        pageTurnRunLoop(2)
    }

    // MARK: - Vertical bar

    func testAVerticalBarTurnsTheLargeTitleIntoTheFixedMediumTitleAndBack() throws {
        let rig = makeRig()
        XCTAssertEqual(rig.page.navigationItem.largeTitleDisplayMode, .automatic, "a phone bar shows the large title")

        rig.duo.hasBar = true
        update(rig)
        XCTAssertTrue(rig.environment.inVerticalBar)
        XCTAssertEqual(rig.page.navigationItem.largeTitleDisplayMode, .never, "a rail has no room for a large title")
        if #available(iOS 26.0, *) {
            XCTAssertEqual(rig.page.navigationItem.attributedTitle.map { String($0.characters) }, "Rail")
            XCTAssertEqual(rig.page.navigationItem.attributedTitle?.runs.first?.uiKit.font?.pointSize ?? 0, 24, accuracy: 0.5,
                           "the title is the fixed medium one")
        }

        rig.duo.hasBar = false
        update(rig)
        XCTAssertFalse(rig.environment.inVerticalBar)
        XCTAssertEqual(rig.page.navigationItem.largeTitleDisplayMode, .automatic)
        if #available(iOS 26.0, *) {
            XCTAssertNotEqual(rig.page.navigationItem.attributedTitle?.runs.first?.uiKit.font?.pointSize, 24, "the plain title is back")
        }
    }

    func testAnInlinePageStaysInlineWhateverTheBar() {
        var configuration = FentonPageConfiguration()
        configuration.titleStyle = .inline
        let rig = makeRig(configuration: configuration)
        rig.duo.hasBar = true
        update(rig)
        XCTAssertEqual(rig.page.navigationItem.largeTitleDisplayMode, .never)
        rig.duo.hasBar = false
        update(rig)
        XCTAssertEqual(rig.page.navigationItem.largeTitleDisplayMode, .never)
    }

    func testASheetPageNeverTakesTheFixedTitle() {
        var configuration = FentonPageConfiguration()
        configuration.surface = .sheet
        let rig = makeRig(configuration: configuration)
        rig.duo.hasBar = true
        update(rig)
        XCTAssertEqual(rig.page.navigationItem.largeTitleDisplayMode, .never)
        if #available(iOS 26.0, *) {
            XCTAssertNotEqual(rig.page.navigationItem.attributedTitle?.runs.first?.uiKit.font?.pointSize, 24, "no fixed font on a sheet")
        }
    }

    // MARK: - Reduce Transparency

    func testReduceTransparencyReachesTheEdgeFadeAndTheSystemEdgeStaysSoft() throws {
        let rig = makeRig(withScroll: true)
        let fade = try XCTUnwrap(rig.page.headerFade)
        XCTAssertFalse(fade.reduceTransparency)

        rig.duo.reduceTransparency = true
        update(rig)
        XCTAssertTrue(rig.environment.reduceTransparency)
        XCTAssertTrue(fade.reduceTransparency, "the page forwards the setting to its fade")
        if FentonHeaderEdgeFade.systemDrawsEdge, #available(iOS 26.0, *), let scroll = rig.page.contentScrollView {
            XCTAssertNil(rig.page.contentView.layer.mask, "the system edge draws it: no mask")
            XCTAssertFalse(scroll.topEdgeEffect.isHidden)
            XCTAssertEqual(scroll.topEdgeEffect.style, .soft, "and the system adapts the effect itself")
        }

        rig.duo.reduceTransparency = false
        update(rig)
        XCTAssertFalse(fade.reduceTransparency)
    }

    func testReduceTransparencyMakesTheMaskedFadeAHardCut() throws {
        // The page picks the era from the running system, so the mask path is exercised on a fade of the same kind the page makes.
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        let fade = FentonHeaderEdgeFade(masking: view, usesSystemEffect: false)
        fade.layoutChanged()
        let soft = try XCTUnwrap(fade.maskStops)
        fade.reduceTransparency = true
        let hard = try XCTUnwrap(fade.maskStops)
        XCTAssertNotEqual(soft.locations, hard.locations, "the ramp shrinks to a cut under Reduce Transparency")
    }

    // MARK: - Fold

    func testAFoldedWindowLeavesTheFullBleedContentViewAndLayoutAlone() {
        let rig = makeRig(withScroll: true)
        rig.page.view.layoutIfNeeded()
        let before = rig.page.contentView.frame
        let counter = PageLayoutCounter.install(on: rig.page.view)
        let size = rig.page.view.bounds.size
        rig.duo.partlyFolded(in: size)
        update(rig)
        XCTAssertNotNil(rig.environment.band, "the fold reached the environment")
        XCTAssertEqual(rig.page.contentView.frame, before, "a page keeps the full width: panes and grids, not pages, sit on the hinge")
        pageTurnRunLoop(2, seconds: 0.2)
        XCTAssertLessThanOrEqual(counter.count, 2, "a fold is not a layout loop")
        let settled = counter.count
        pageTurnRunLoop(2, seconds: 0.2)
        XCTAssertEqual(counter.count, settled, "and nothing keeps laying out afterwards")
    }

    func testTheSideInsetsFollowTheRailNotTheFold() {
        let rig = makeRig()
        rig.page.sideInsetsOverride = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 56)
        rig.page.view.layoutIfNeeded()
        let bounds = rig.page.view.bounds
        XCTAssertEqual(rig.page.contentView.frame.width, bounds.width - 56, accuracy: 0.5)
        rig.duo.partlyFolded(in: bounds.size)
        update(rig)
        XCTAssertEqual(rig.page.contentView.frame.width, bounds.width - 56, accuracy: 0.5, "the fold changes nothing about the rail inset")
    }
}
#endif
