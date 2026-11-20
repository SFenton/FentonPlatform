#if os(iOS)
import FentonAppleCore
@testable import FentonUIKit
import UIKit
import XCTest

@MainActor
final class ColumnsTests: XCTestCase {
    private var rigs: [ColumnsRig] = []

    override func tearDown() async throws {
        rigs.forEach { $0.tearDown() }
        rigs = []
        try await super.tearDown()
    }

    private func makeRig(size: CGSize = CGSize(width: 1024, height: 768), wide: Bool = true,
                         appearance: FentonColumnsAppearance = FentonColumnsAppearance()) -> ColumnsRig {
        let rig = ColumnsRig(size: size, wide: wide, appearance: appearance)
        rigs.append(rig)
        return rig
    }

    // MARK: - Opening

    func testNarrowRootFillsTheContainerAndAShownPageIsPushedOnTheStack() {
        let rig = makeRig(wide: false)
        XCTAssertFalse(rig.columns.isWide)
        XCTAssertEqual(rig.root.view.frame, rig.columns.view.bounds)
        let page = rig.page("detail")
        rig.columns.show(page, sender: rig.root)
        XCTAssertTrue(rig.navigation.viewControllers.last === page, "a narrow window pushes on the enclosing stack")
        XCTAssertTrue(rig.columns.entries.isEmpty, "no entry is kept")
        let form = rig.page("form")
        rig.columns.open(form, tag: nil, animated: false, pushesWhenNarrow: false)
        XCTAssertFalse(rig.navigation.viewControllers.contains(form), "a page the owner re-presents is dropped, not pushed")
    }

    func testOpenAppendsAndShowFromTheLeftColumnReplacesWhatIsOnTheRight() {
        let rig = makeRig()
        let a = rig.page("a"), b = rig.page("b"), c = rig.page("c")
        rig.columns.open(a, tag: nil, animated: false)
        XCTAssertEqual(rig.columns.entries.count, 1)
        // A tap in the right column drills.
        rig.columns.show(b, sender: a)
        XCTAssertEqual(rig.columns.entries.map(\.controller), [a, b])
        // A tap in the left column (the root, depth 0) cuts back to the root and appends.
        rig.columns.show(c, sender: rig.root)
        XCTAssertEqual(rig.columns.entries.map(\.controller), [c])
        XCTAssertEqual(rig.columns.depth(of: rig.root), 0)
        XCTAssertEqual(rig.columns.depth(of: c), 1)
        XCTAssertEqual(rig.columns.depth(of: c.view), 0, "anything that is not a controller counts as the root")
    }

    func testShowDetailViewControllerIsShow() {
        let rig = makeRig()
        let a = rig.page("a")
        rig.columns.showDetailViewController(a, sender: rig.root)
        XCTAssertTrue(LaneBHost.spin(until: { rig.columns.entries.map(\.controller) == [a] }))
    }

    func testTheWindowShowsTheLastTwoColumns() {
        let rig = makeRig()
        let a = rig.page("a"), b = rig.page("b")
        let columns = rig.columns
        columns.open(a, tag: nil, animated: false)
        rig.settle()
        let width = rig.size.width
        let half = (width - 1) / 2
        XCTAssertEqual(rig.root.view.frame, CGRect(x: 0, y: 0, width: half, height: columns.view.bounds.height))
        XCTAssertEqual(columns.entries[0].host.frame.minX, half + 1, accuracy: 0.5)
        columns.open(b, tag: nil, atDepth: 1, animated: false)
        rig.settle()
        XCTAssertLessThan(rig.root.view.frame.maxX, 0.5, "the root slides off to the left once two pages are open")
        XCTAssertEqual(columns.entries[0].host.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(columns.entries[1].host.frame.minX, half + 1, accuracy: 0.5)
    }

    func testPagesAreMovedByFrameAndNeverReparented() {
        let rig = makeRig()
        let a = rig.page("a"), b = rig.page("b")
        rig.columns.open(a, tag: nil, animated: false)
        rig.settle()
        let host = rig.columns.entries[0].host
        XCTAssertTrue(a.view.superview === host)
        XCTAssertTrue(a.parent === rig.columns)
        rig.columns.open(b, tag: nil, atDepth: 1, animated: false)
        rig.settle()
        XCTAssertTrue(a.view.superview === host, "drilling moves the host's frame, the page's view stays in it")
        XCTAssertTrue(a.parent === rig.columns)
        XCTAssertTrue(rig.root.view.superview === rig.columns.view)
        // An animated transition does not reparent either.
        let c = rig.page("c")
        rig.columns.open(c, tag: nil, atDepth: 2, animated: true)
        XCTAssertTrue(a.view.superview === host)
        XCTAssertTrue(LaneBHost.spin(until: { !rig.columns.isTransitioning }))
        XCTAssertTrue(a.view.superview === host)
    }

    func testSetDetailReplacesAndNilClears() {
        let rig = makeRig()
        let a = rig.page("a"), b = rig.page("b")
        rig.columns.setDetail(a, animated: false)
        rig.columns.setDetail(b, tag: "b", animated: false)
        XCTAssertEqual(rig.columns.entries.map(\.controller), [b])
        XCTAssertEqual(rig.columns.entries.first?.tag, "b")
        rig.columns.setDetail(nil, animated: false)
        XCTAssertTrue(rig.columns.entries.isEmpty)
        rig.columns.setDetail(nil, animated: false)
        let narrow = makeRig(wide: false)
        narrow.columns.setDetail(narrow.page("x"), animated: false)
        XCTAssertTrue(narrow.columns.entries.isEmpty, "nothing is kept when the window is narrow")
    }

    func testRemoveTakesOnlyTheOpenPageOnTheRight() {
        let rig = makeRig()
        let a = rig.page("a"), b = rig.page("b")
        rig.columns.open(a, tag: nil, animated: false)
        rig.columns.open(b, tag: nil, atDepth: 1, animated: false)
        rig.columns.remove(a, animated: false)
        XCTAssertEqual(rig.columns.entries.count, 2, "a is not the page on the right")
        rig.columns.remove(b, animated: false)
        XCTAssertEqual(rig.columns.entries.map(\.controller), [a])
        XCTAssertNil(b.parent)
        XCTAssertNil(b.view.superview?.superview, "its host left the columns")
    }

    // MARK: - Back and Close

    func testBackPopsOneAndCloseEmptiesTheColumnsAndBothReportTheTaggedDepth() {
        let rig = makeRig()
        var depths: [Int] = []
        var closed: [String] = []
        rig.columns.onUserPop = { depths.append($0) }
        rig.columns.open(rig.page("a"), tag: "a", animated: false, onUserClose: { closed.append("a") })
        rig.columns.open(rig.page("b"), tag: "b", atDepth: 1, animated: false, onUserClose: { closed.append("b") })
        rig.columns.open(rig.page("local"), tag: nil, atDepth: 2, animated: false)
        rig.columns.popTop(animated: false)
        XCTAssertEqual(depths, [2], "the local page above two tagged pages is gone: two tagged remain")
        rig.columns.closeAll(animated: false)
        XCTAssertEqual(depths, [2, 0])
        XCTAssertTrue(rig.columns.entries.isEmpty)
        XCTAssertEqual(closed, ["a", "b"], "each person-closed page hears it")
    }

    func testAnOwnerRemovalIsNotAUserPop() {
        let rig = makeRig()
        var popped = false
        rig.columns.onUserPop = { _ in popped = true }
        let a = rig.page("a")
        rig.columns.open(a, tag: nil, animated: false)
        rig.columns.remove(a, animated: false)
        rig.columns.setDetail(rig.page("b"), animated: false)
        rig.columns.setDetail(nil, animated: false)
        XCTAssertFalse(popped)
    }

    func testTheBarHostGetsBackWhenDrilledCloseOnTheFirstPageAndNothingWhenEmpty() {
        let rig = makeRig()
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        XCTAssertEqual(rig.barHost.items.last?.accessibilityIdentifier, "column.close")
        XCTAssertEqual(rig.barHost.items.last?.accessibilityLabel, "Close")
        rig.columns.open(rig.page("b"), tag: nil, atDepth: 1, animated: false)
        XCTAssertEqual(rig.barHost.items.last?.accessibilityIdentifier, "column.back")
        XCTAssertEqual(rig.barHost.items.last?.accessibilityLabel, "Back")
        XCTAssertTrue(rig.barHost.items.last === rig.columns.exitBarItem)
        rig.columns.closeAll(animated: false)
        XCTAssertEqual(rig.barHost.items.count, 0)
    }

    func testThePagesOwnBarItemsRideInTheColumnGroupAndFollowChanges() {
        let rig = makeRig()
        let page = rig.page("a")
        let refresh = UIBarButtonItem(systemItem: .refresh)
        page.navigationItem.leftBarButtonItems = [refresh]
        rig.columns.open(page, tag: nil, animated: false)
        XCTAssertTrue(rig.barHost.items.first === refresh)
        XCTAssertTrue(rig.barHost.items.last === rig.columns.exitBarItem)
        let add = UIBarButtonItem(systemItem: .add)
        page.navigationItem.rightBarButtonItems = [add]
        XCTAssertTrue(LaneBHost.spin(until: { rig.barHost.items.contains { $0 === add } }))
    }

    func testBackAndCloseItemsPerformTheirAction() {
        let rig = makeRig()
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        rig.columns.open(rig.page("b"), tag: nil, atDepth: 1, animated: false)
        let item = rig.columns.exitBarItem
        item.primaryAction?.performWithSender(item, target: nil)
        XCTAssertEqual(rig.columns.entries.count, 1, "Back")
        item.primaryAction?.performWithSender(item, target: nil)
        XCTAssertEqual(rig.columns.entries.count, 0, "Close")
    }

    func testCustomAppearanceWordsAndHairline() {
        var appearance = FentonColumnsAppearance()
        appearance.backLabel = "Retour"
        appearance.closeLabel = "Fermer"
        appearance.ground = .red
        appearance.hairline = .blue
        let rig = makeRig(appearance: appearance)
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        XCTAssertEqual(rig.barHost.items.last?.accessibilityLabel, "Fermer")
        let host = rig.columns.entries[0].host
        XCTAssertEqual(host.backgroundColor, .red)
        XCTAssertEqual(host.subviews.count, 2, "the page's view and the hairline")
        XCTAssertEqual(host.subviews.last?.backgroundColor, .blue)
        XCTAssertEqual(host.subviews.last?.isAccessibilityElement, false)
    }

    // MARK: - Guards

    func testABlockingPageStopsBackCloseAndTheEdgePan() {
        let rig = makeRig()
        let page = GuardedPage()
        page.columnPopDecision = .block
        rig.columns.open(page, tag: nil, animated: false)
        rig.columns.pageStateChanged()
        XCTAssertFalse(rig.columns.exitBarItem.isEnabled, "Back and Close are dimmed while a save runs")
        rig.columns.popTop(animated: false)
        rig.columns.closeAll(animated: false)
        XCTAssertEqual(rig.columns.entries.count, 1)
        rig.columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        XCTAssertFalse(rig.columns.isTransitioning, "the edge pan does not start")
        page.columnPopDecision = .allow
        rig.columns.pageStateChanged()
        XCTAssertTrue(rig.columns.exitBarItem.isEnabled)
        rig.columns.popTop(animated: false)
        XCTAssertTrue(rig.columns.entries.isEmpty)
    }

    func testAPageWithEditsAsksBeforeBackAndCloseAndTheEdgePanStaysOff() throws {
        let rig = makeRig()
        let page = GuardedPage()
        page.columnPopDecision = .confirmDiscard
        rig.columns.open(page, tag: nil, animated: false)
        rig.columns.popTop(animated: false)
        XCTAssertEqual(rig.columns.entries.count, 1, "Back waits for the answer")
        let dialog = try XCTUnwrap(page.presentedViewController as? UIAlertController)
        XCTAssertEqual(dialog.title, "Discard changes?")
        XCTAssertEqual(dialog.actions.map(\.title), ["Discard Changes", "Keep Editing"])
        XCTAssertEqual(dialog.actions.map(\.style), [.destructive, .cancel])
        rig.columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        XCTAssertFalse(rig.columns.isTransitioning, "a drag never discards")
    }

    func testTheDiscardCopyIsTheAppsToChange() throws {
        var appearance = FentonColumnsAppearance()
        appearance.discardCopy.title = "Verwerfen?"
        let rig = makeRig(appearance: appearance)
        let page = GuardedPage()
        page.columnPopDecision = .confirmDiscard
        rig.columns.open(page, tag: nil, animated: false)
        rig.columns.closeAll(animated: false)
        XCTAssertEqual((page.presentedViewController as? UIAlertController)?.title, "Verwerfen?")
    }

    func testAnExitRequestingPageDefersBackThroughItsApproval() {
        let rig = makeRig()
        let page = ExitRequestingPage()
        let other = rig.page("other")
        rig.columns.open(other, tag: nil, animated: false)
        rig.columns.open(page, tag: nil, atDepth: 1, animated: false)
        rig.columns.popTop(animated: false)
        XCTAssertEqual(page.requests.count, 1)
        XCTAssertEqual(page.requests.first, [page])
        XCTAssertEqual(rig.columns.entries.count, 2, "nothing leaves until the page approves")
        page.approvals[0]()
        XCTAssertEqual(rig.columns.entries.map(\.controller), [other])
        page.approvals[0]()
        XCTAssertEqual(rig.columns.entries.count, 1, "a repeated approval does nothing")
    }

    func testCloseAsksOnceListingEveryPageThatWouldLeave() {
        let rig = makeRig()
        let first = rig.page("first")
        let page = ExitRequestingPage()
        rig.columns.open(first, tag: nil, animated: false)
        rig.columns.open(page, tag: nil, atDepth: 1, animated: false)
        rig.columns.closeAll(animated: false)
        XCTAssertEqual(page.requests, [[first, page]])
        page.approvals[0]()
        XCTAssertTrue(rig.columns.entries.isEmpty)
    }

    func testAnApprovalAfterTheStackMovedOnIsIgnored() {
        let rig = makeRig()
        let page = ExitRequestingPage()
        rig.columns.open(page, tag: nil, animated: false)
        rig.columns.popTop(animated: false)
        rig.columns.setDetail(rig.page("replacement"), animated: false)
        page.approvals[0]()
        XCTAssertEqual(rig.columns.entries.count, 1, "the page asked about is no longer the open one")
        XCTAssertEqual(rig.columns.entries.first?.controller.title, "replacement")
    }

    // MARK: - Narrow and wide

    func testTurningNarrowHandsLocalPagesToTheStackAndTurningWideRestoresThem() {
        let rig = makeRig()
        var wideChanges: [Bool] = []
        rig.columns.onWideChange = { wideChanges.append($0) }
        let a = rig.page("a"), b = rig.page("b"), tagged = rig.page("tagged")
        rig.columns.open(a, tag: nil, animated: false)
        rig.columns.open(b, tag: nil, atDepth: 1, animated: false)
        rig.columns.open(tagged, tag: "route", atDepth: 2, animated: false)

        rig.columns.setWide(false)
        rig.settle()
        XCTAssertTrue(rig.columns.entries.isEmpty)
        XCTAssertEqual(rig.root.view.frame, rig.columns.view.bounds)
        XCTAssertTrue(LaneBHost.spin(until: { rig.navigation.viewControllers.count == 3 }))
        XCTAssertEqual(rig.navigation.viewControllers.dropFirst().map { $0 }, [a, b], "tagged pages are the owner's to put back")

        rig.columns.setWide(true)
        XCTAssertTrue(LaneBHost.spin(until: { rig.navigation.viewControllers.count == 1 }))
        XCTAssertEqual(rig.columns.entries.map(\.controller), [a, b], "a rotation or fold loses nothing")
        XCTAssertEqual(wideChanges, [false, true])
    }

    func testAPagesOwnBarItemsSurviveNarrowAndWideAlongsideTheBackOrCloseItem() {
        let rig = makeRig()
        let page = rig.page("detail")
        let add = UIBarButtonItem(systemItem: .add)
        let share = UIBarButtonItem(systemItem: .action)
        page.navigationItem.rightBarButtonItems = [add, share]
        rig.columns.open(page, tag: nil, animated: false)
        XCTAssertTrue(rig.barHost.items.contains { $0 === add }, "wide: the page's items ride in the column group")
        XCTAssertTrue(rig.barHost.items.last === rig.columns.exitBarItem, "beside Close")
        XCTAssertEqual(page.navigationItem.rightBarButtonItems, [add, share], "the page keeps its own items")

        rig.columns.setWide(false)
        rig.settle()
        XCTAssertTrue(LaneBHost.spin(until: { rig.navigation.viewControllers.contains(page) }))
        XCTAssertEqual(page.navigationItem.rightBarButtonItems, [add, share], "narrow: the stack shows the page's trailing items")

        rig.columns.setWide(true)
        XCTAssertTrue(LaneBHost.spin(until: { rig.columns.entries.map(\.controller) == [page] }))
        rig.settle()
        XCTAssertEqual(page.navigationItem.rightBarButtonItems, [add, share], "wide again: still there")
        XCTAssertTrue(rig.barHost.items.contains { $0 === add && $0 !== rig.columns.exitBarItem })
        XCTAssertTrue(rig.barHost.items.last === rig.columns.exitBarItem)
    }

    func testCreatingColumnsDoesNotLoadTheRootControllersView() {
        final class Root: UIViewController {
            private(set) var loads = 0
            override func loadView() {
                loads += 1
                view = UIView()
            }
        }
        let root = Root()
        let columns = FentonColumnsViewController(root: root, environment: FentonWindowEnvironment()) { UIViewController() }
        XCTAssertFalse(root.isViewLoaded, "init leaves the root's view alone")
        XCTAssertEqual(root.loads, 0)
        columns.loadViewIfNeeded()
        XCTAssertTrue(root.view.superview === columns.view, "it loads with the columns' own view")
        XCTAssertEqual(root.loads, 1)
    }

    func testAColumnsControllerCanTakeAPlainViewAsItsRoot() {
        let environment = FentonWindowEnvironment()
        let rootView = UIView()
        let columns = FentonColumnsViewController(rootView: rootView, environment: environment) { UIViewController() }
        let window = pageTestWindow(columns, size: CGSize(width: 1024, height: 768))
        window.layoutIfNeeded()
        defer { window.isHidden = true }
        XCTAssertTrue(rootView.superview === columns.view, "the view fills the container")
        XCTAssertEqual(rootView.frame, columns.view.bounds)
        XCTAssertTrue(columns.children.isEmpty, "no controller became its child")
        columns.setWide(true)
        let detail = UIViewController()
        columns.open(detail, tag: nil, animated: false)
        window.layoutIfNeeded()
        XCTAssertTrue(detail.parent === columns)
        XCTAssertLessThan(rootView.frame.maxX, detail.view.frame.maxX + 1, "the root stays the leading column")
    }

    func testPushesCollapsedPagesOffLeavesTheStackAlone() {
        let rig = makeRig()
        rig.columns.pushesCollapsedPages = false
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        rig.columns.setWide(false)
        LaneBHost.spin(0.1)
        XCTAssertEqual(rig.navigation.viewControllers.count, 1)
    }

    func testAPageThatDoesNotPushWhenNarrowIsLeftBehind() {
        let rig = makeRig()
        let form = rig.page("form")
        rig.columns.open(form, tag: nil, animated: false, pushesWhenNarrow: true)
        rig.columns.entries.first?.pushesWhenNarrow = false
        rig.columns.setWide(false)
        LaneBHost.spin(0.1)
        XCTAssertEqual(rig.navigation.viewControllers.count, 1)
    }

    func testSetWideToTheSameValueDoesNothing() {
        let rig = makeRig()
        var count = 0
        rig.columns.onWideChange = { _ in count += 1 }
        rig.columns.setWide(true)
        XCTAssertEqual(count, 0)
    }

    func testAdoptOpensPagesAfterTheTaggedOnesAndIsIgnoredWhenNarrow() {
        let rig = makeRig()
        let a = rig.page("a"), b = rig.page("b")
        rig.columns.adopt([a, b])
        XCTAssertEqual(rig.columns.entries.map(\.controller), [a, b])
        let narrow = makeRig(wide: false)
        narrow.columns.adopt([narrow.page("x")])
        XCTAssertTrue(narrow.columns.entries.isEmpty)
    }

    // MARK: - Geometry

    func testPartlyFoldedColumnsSitOnTheHingeBandAndMatchTheSplitPolicy() {
        let size = CGSize(width: 868, height: 400)
        let rig = makeRig(size: size)
        rig.duo.partlyFolded(in: size)
        rig.refreshSignals()
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        rig.settle()
        let expected = FentonSplitPolicy().columnWidths(container: CGRect(origin: .zero, size: size), hinge: rig.environment.band, gutter: 1)
        XCTAssertTrue(expected.isHinge)
        XCTAssertEqual(rig.root.view.frame.width, expected.leadingWidth, accuracy: 0.5)
        let host = rig.columns.entries[0].host
        XCTAssertEqual(host.frame.minX, expected.leadingWidth + expected.bandWidth, accuracy: 0.5)
        XCTAssertEqual(host.frame.width, expected.trailingWidth, accuracy: 0.5)
        XCTAssertEqual(expected.leadingWidth + expected.bandWidth + expected.trailingWidth, size.width, accuracy: 0.5)
    }

    func testFlatColumnsDivideAtTheMidpointWithTheGutter() {
        let size = CGSize(width: 868, height: 400)
        let rig = makeRig(size: size)
        rig.duo.flat(in: size)
        rig.refreshSignals()
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        rig.settle()
        let expected = FentonSplitPolicy().columnWidths(container: CGRect(origin: .zero, size: size), hinge: rig.environment.band, gutter: 1)
        XCTAssertFalse(expected.isHinge, "a flat device has no band to sit on")
        XCTAssertEqual(rig.root.view.frame.width, expected.leadingWidth, accuracy: 0.5)
        XCTAssertEqual(rig.columns.entries[0].host.frame.width, expected.trailingWidth, accuracy: 0.5)
        XCTAssertEqual(expected.leadingWidth + expected.bandWidth + expected.trailingWidth, size.width, accuracy: 0.5)
    }

    func testAPostureChangeMovesTheColumnsWithoutTouchingTheEntries() {
        let size = CGSize(width: 868, height: 400)
        let rig = makeRig(size: size)
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        rig.settle()
        let before = rig.columns.entries[0].host
        rig.duo.partlyFolded(in: size)
        rig.refreshSignals()
        XCTAssertTrue(rig.columns.entries[0].host === before)
        XCTAssertEqual(rig.columns.entries[0].host.frame.minX, 435, accuracy: 0.5, "the band is 433 to 435")
    }

    func testHighContrastDrawsTheBandBetweenColumnsOnlyWithoutAHinge() {
        let rig = makeRig()
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        rig.settle()
        let band = rig.columns.view.subviews.first { $0.isAccessibilityElement == false && $0.accessibilityElementsHidden && $0.frame.width <= 1.5 }
        XCTAssertNotNil(band)
        XCTAssertEqual(band?.isHidden, true, "at normal contrast the hairline suffices")
    }

    // MARK: - Tags and reconcile

    func testReconcileKeepsTheCommonPrefixAndReplacesTheRest() {
        let rig = makeRig()
        var made: [String] = []
        let make: (AnyHashable) -> UIViewController = { tag in
            made.append(String(describing: tag))
            return rig.page(String(describing: tag))
        }
        rig.columns.reconcile(tags: ["a", "b"], make: make, animated: false)
        XCTAssertEqual(rig.columns.entries.compactMap(\.tag), ["a", "b"])
        XCTAssertEqual(made, ["a", "b"])
        let first = rig.columns.entries[0].controller
        rig.columns.reconcile(tags: ["a", "c"], make: make, animated: false)
        XCTAssertEqual(rig.columns.entries.compactMap(\.tag), ["a", "c"])
        XCTAssertTrue(rig.columns.entries[0].controller === first, "the common prefix keeps its page")
        XCTAssertEqual(made, ["a", "b", "c"])
        rig.columns.reconcile(tags: ["a", "c"], make: make, animated: false)
        XCTAssertEqual(made, ["a", "b", "c"], "no change, no pages made")
        rig.columns.reconcile(tags: [], make: make, animated: false)
        XCTAssertTrue(rig.columns.entries.isEmpty)
    }

    func testReconcileLeavesALocalPageAboveMatchingTags() {
        let rig = makeRig()
        rig.columns.reconcile(tags: ["a"], make: { rig.page("\($0)") }, animated: false)
        let local = rig.page("local")
        rig.columns.open(local, tag: nil, atDepth: 1, animated: false)
        rig.columns.reconcile(tags: ["a"], make: { rig.page("\($0)") }, animated: false)
        XCTAssertEqual(rig.columns.entries.count, 2)
        XCTAssertTrue(rig.columns.entries.last?.controller === local)
    }

    func testReconcileIsIgnoredWhenNarrow() {
        let rig = makeRig(wide: false)
        rig.columns.reconcile(tags: ["a"], make: { rig.page("\($0)") }, animated: false)
        XCTAssertTrue(rig.columns.entries.isEmpty)
    }

    // MARK: - Accessibility

    func testVoiceOverSeesOnlyTheColumnsInTheWindow() {
        let rig = makeRig()
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        rig.columns.open(rig.page("b"), tag: nil, atDepth: 1, animated: false)
        rig.columns.open(rig.page("c"), tag: nil, atDepth: 2, animated: false)
        let hosts = rig.columns.entries.map(\.host)
        XCTAssertTrue(rig.root.view.accessibilityElementsHidden)
        XCTAssertTrue(hosts[0].accessibilityElementsHidden)
        XCTAssertFalse(hosts[1].accessibilityElementsHidden)
        XCTAssertFalse(hosts[2].accessibilityElementsHidden)
        XCTAssertEqual(hosts[2].accessibilityIdentifier, "split.trailing")
        XCTAssertNil(hosts[1].accessibilityIdentifier)
        rig.columns.trailingIdentifier = "todo.pane"
        rig.columns.popTop(animated: false)
        XCTAssertEqual(rig.columns.entries.last?.host.accessibilityIdentifier, "todo.pane")
    }

    // MARK: - The empty state

    func testThePlaceholderFillsTheRightColumnWhileNothingIsOpen() {
        let rig = makeRig()
        let placeholder = rig.columns.children.first { $0 !== rig.root }
        XCTAssertNotNil(placeholder)
        XCTAssertEqual(placeholder?.view.accessibilityIdentifier, "placeholder")
        let trailing = rig.columns.view.bounds.width - rig.root.view.frame.width - 1
        XCTAssertEqual(placeholder?.view.frame.width ?? 0, trailing, accuracy: 0.5)
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        XCTAssertNil(placeholder?.parent, "an open page replaces the empty state")
        rig.columns.closeAll(animated: false)
        rig.settle()
        XCTAssertNotNil(rig.columns.children.first { $0 !== rig.root }, "closing brings it back")
    }

    func testTheEmptyStateFadesOutBeforeTheFirstPageComesInAndFinalStateMatches() {
        let rig = makeRig()
        let a = rig.page("a")
        rig.columns.open(a, tag: nil, animated: true)
        XCTAssertTrue(rig.columns.isTransitioning)
        XCTAssertTrue(rig.columns.entries.isEmpty, "the page waits for the empty state to leave")
        XCTAssertTrue(LaneBHost.spin(until: { !rig.columns.isTransitioning }))
        XCTAssertEqual(rig.columns.entries.map(\.controller), [a])
        rig.columns.closeAll(animated: true)
        XCTAssertTrue(LaneBHost.spin(until: { !rig.columns.isTransitioning }))
        XCTAssertTrue(rig.columns.entries.isEmpty)
        let placeholder = rig.columns.children.first { $0 !== rig.root }
        XCTAssertEqual(placeholder?.view.alpha, 1)
    }

    func testRapidOpensSettleOnTheLastAndSettledFires() {
        let rig = makeRig()
        var settled = 0
        rig.columns.onSettled = { settled += 1 }
        let a = rig.page("a"), b = rig.page("b")
        rig.columns.open(a, tag: nil, animated: true)
        rig.columns.open(b, tag: nil, animated: true)
        XCTAssertTrue(LaneBHost.spin(until: { !rig.columns.isTransitioning }))
        LaneBHost.spin(0.4)
        XCTAssertEqual(rig.columns.entries.map(\.controller), [b])
        XCTAssertGreaterThan(settled, 0)
    }

    // MARK: - Reduce Motion

    func testReduceMotionCrossFadesInPlaceInsteadOfSliding() {
        let rig = makeRig()
        let a = rig.page("a")
        rig.columns.open(a, tag: nil, animated: false)
        rig.settle()
        rig.duo.reduceMotion = true
        rig.refreshSignals()
        XCTAssertTrue(rig.environment.reduceMotion)
        let b = rig.page("b")
        rig.columns.open(b, tag: nil, atDepth: 1, animated: true)
        let entry = rig.columns.entries[1]
        // Only opacity animates: the page is already in its column, so nothing slides.
        let keys = entry.host.layer.animationKeys() ?? []
        XCTAssertTrue(keys.contains("opacity"), "the new page fades in: \(keys)")
        XCTAssertFalse(keys.contains("position"), "and does not slide: \(keys)")
        XCTAssertTrue(LaneBHost.spin(until: { !rig.columns.isTransitioning }))
        XCTAssertEqual(entry.host.alpha, 1)
        // No snapshot of a page that jumped is left behind.
        XCTAssertFalse(rig.columns.view.subviews.contains { $0 is UIVisualEffectView || String(describing: type(of: $0)).contains("Snapshot") })
    }

    func testWithoutReduceMotionADrilledPageSlidesIn() {
        let rig = makeRig()
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        rig.settle()
        rig.columns.open(rig.page("b"), tag: nil, atDepth: 1, animated: true)
        let keys = rig.columns.entries[1].host.layer.animationKeys() ?? []
        XCTAssertTrue(keys.contains("position"), "the new page slides in from the right: \(keys)")
        XCTAssertTrue(LaneBHost.spin(until: { !rig.columns.isTransitioning }))
        XCTAssertEqual(rig.columns.entries[1].host.alpha, 1)
    }

    func testReduceMotionStillLetsTheEdgePanPop() {
        let rig = makeRig()
        rig.duo.reduceMotion = true
        rig.refreshSignals()
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        rig.settle()
        rig.columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        XCTAssertTrue(rig.columns.isTransitioning)
        rig.columns.handleEdgePan(state: .changed, translation: 600, velocity: 0)
        rig.columns.handleEdgePan(state: .ended, translation: 600, velocity: 0)
        XCTAssertTrue(LaneBHost.spin(until: { rig.columns.entries.isEmpty && !rig.columns.isTransitioning }))
    }

    // MARK: - Edge pan

    func testTheEdgePanTakesOverOnlyWhileWideWithAPageToClose() {
        let rig = makeRig()
        XCTAssertFalse(rig.columns.takesEdgePan)
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        XCTAssertTrue(rig.columns.takesEdgePan)
        let pan = rig.columns.view.gestureRecognizers?.compactMap { $0 as? UIScreenEdgePanGestureRecognizer }.first
        XCTAssertEqual(pan?.edges, .left)
        XCTAssertEqual(pan?.isEnabled, true)
        rig.columns.setWide(false)
        XCTAssertFalse(rig.columns.takesEdgePan)
        XCTAssertEqual(pan?.isEnabled, false)
    }

    func testAFarDragCompletesTheBackAndAShortOneReverses() {
        let rig = makeRig()
        var depths: [Int] = []
        rig.columns.onUserPop = { depths.append($0) }
        rig.columns.open(rig.page("a"), tag: "a", animated: false)
        rig.columns.open(rig.page("b"), tag: "b", atDepth: 1, animated: false)
        rig.settle()
        let width = rig.columns.view.bounds.width

        rig.columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        rig.columns.handleEdgePan(state: .changed, translation: width * 0.2, velocity: 0)
        rig.columns.handleEdgePan(state: .ended, translation: width * 0.2, velocity: 100)
        XCTAssertTrue(LaneBHost.spin(until: { !rig.columns.isTransitioning }))
        XCTAssertEqual(rig.columns.entries.count, 2, "a short, slow drag reverses")
        XCTAssertEqual(depths, [])

        rig.columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        rig.columns.handleEdgePan(state: .changed, translation: width * 0.2, velocity: 0)
        rig.columns.handleEdgePan(state: .ended, translation: width * 0.2, velocity: 900)
        XCTAssertTrue(LaneBHost.spin(until: { !rig.columns.isTransitioning }))
        XCTAssertEqual(rig.columns.entries.count, 1, "a flick completes")
        XCTAssertEqual(depths, [1])

        rig.columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        rig.columns.handleEdgePan(state: .changed, translation: width * 0.8, velocity: 0)
        rig.columns.handleEdgePan(state: .ended, translation: width * 0.8, velocity: 0)
        XCTAssertTrue(LaneBHost.spin(until: { !rig.columns.isTransitioning }))
        XCTAssertTrue(rig.columns.entries.isEmpty, "past halfway completes")
        XCTAssertEqual(depths, [1, 0])
        XCTAssertNotNil(rig.columns.children.first { $0 !== rig.root }, "the empty state returns")
    }

    func testACancelledDragReverses() {
        let rig = makeRig()
        rig.columns.open(rig.page("a"), tag: nil, animated: false)
        rig.settle()
        rig.columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        rig.columns.handleEdgePan(state: .changed, translation: 500, velocity: 0)
        rig.columns.handleEdgePan(state: .cancelled, translation: 500, velocity: 0)
        XCTAssertTrue(LaneBHost.spin(until: { !rig.columns.isTransitioning }))
        XCTAssertEqual(rig.columns.entries.count, 1)
        // Ending with no drag in progress does nothing.
        rig.columns.handleEdgePan(state: .ended, translation: 0, velocity: 0)
        rig.columns.handleEdgePan(state: .possible, translation: 0, velocity: 0)
    }

    func testTheEdgePanOfAnExitRequestingPageWaitsForItsApproval() {
        let rig = makeRig()
        let page = ExitRequestingPage()
        rig.columns.open(page, tag: nil, animated: false)
        rig.settle()
        rig.columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        XCTAssertEqual(page.requests.count, 1)
        XCTAssertFalse(rig.columns.isTransitioning, "the page has not approved: no scrub starts")
        page.approvals[0]()
        XCTAssertTrue(LaneBHost.spin(until: { rig.columns.entries.isEmpty && !rig.columns.isTransitioning }))
    }

    func testTheEdgePanDoesNothingWhenNarrowOrEmpty() {
        let rig = makeRig()
        rig.columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        XCTAssertFalse(rig.columns.isTransitioning)
        let narrow = makeRig(wide: false)
        narrow.columns.handleEdgePan(state: .began, translation: 0, velocity: 0)
        XCTAssertFalse(narrow.columns.isTransitioning)
    }

    // MARK: - The column title

    func testTheColumnTitleReservesRoomOnceAndGivesItBack() {
        let page = UIViewController()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scroll.contentSize = CGSize(width: 400, height: 3000)
        page.loadViewIfNeeded()
        page.view.frame = scroll.frame
        page.view.addSubview(scroll)
        let header = FentonColumnTitleHeader()
        header.attach(to: scroll, in: page, host: page.view, title: "Rooms")
        let reserved = page.additionalSafeAreaInsets.top
        XCTAssertGreaterThan(reserved, 0)
        XCTAssertEqual(header.text, "Rooms")
        XCTAssertTrue(header.superview === page.view)
        XCTAssertTrue(header.accessibilityTraits.contains(.header))
        header.attach(to: scroll, in: page, host: page.view, title: "Renamed")
        XCTAssertEqual(page.additionalSafeAreaInsets.top, reserved, "attaching again adds no room")
        XCTAssertEqual(header.text, "Renamed")
        header.attach(to: scroll, in: page, host: page.view, title: nil)
        XCTAssertTrue(header.isHidden)
        scroll.contentOffset = CGPoint(x: 0, y: reserved * 2)
        header.place()
        XCTAssertEqual(header.alpha, 0, "the heading has scrolled away")
        header.detach()
        XCTAssertEqual(page.additionalSafeAreaInsets.top, 0)
        XCTAssertNil(header.superview)
        header.detach()
        XCTAssertEqual(page.additionalSafeAreaInsets.top, 0)
    }

    func testTheDiscardCopyDefaultsAreNeutral() {
        let copy = FentonDiscardCopy()
        XCTAssertEqual(copy.title, "Discard changes?")
        XCTAssertEqual(copy.discard, "Discard Changes")
        XCTAssertEqual(copy.keepEditing, "Keep Editing")
        XCTAssertEqual(FentonColumnPopDecision.allow, .allow)
    }
}
#endif
