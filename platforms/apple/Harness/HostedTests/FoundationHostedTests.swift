@testable import FentonAppleHarness
import FentonAppleCore
@testable import FentonUIKit
import UIKit
import XCTest

/// The foundation fixture wired as an app would wire it: the scene delegate, the root, the shell page, the columns and the list. These
/// run inside the harness app (a hosted bundle), so the fixture's own types are visible.
@MainActor
final class FoundationHostedTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    /// The fixture's root in a window of `size`, forced to the regular width class a landscape iPad has (the host scene's own class
    /// follows the simulator, which would make a phone run this as compact).
    private func makeRoot(size: CGSize, regular: Bool = true) -> FoundationRootViewController {
        let root = FoundationRootViewController()
        root.traitOverrides.horizontalSizeClass = regular ? .regular : .compact
        root.dismissesLaunchGroundOnFirstAppearance = false
        root.setContent(root.makeContent())
        windows.append(pageTestWindow(root, size: size))
        LaneBHost.spin(0.1)
        return root
    }

    // MARK: - Scene delegate

    func testTheSceneDelegatePathBuildsTheFoundationRootAndItsContent() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let delegate = FoundationSceneDelegate()
        delegate.installWindow(in: scene)
        let window = try XCTUnwrap(delegate.window)
        windows.append(window)
        let root = try XCTUnwrap(window.rootViewController as? FoundationRootViewController)
        XCTAssertTrue(root.content is FentonNavigationController)
        XCTAssertNotNil(root.shell)
        XCTAssertEqual(root.shell?.title, "Foundation")
        XCTAssertEqual(FoundationIdentifiers.launchArgument, "--foundation")
    }

    // MARK: - The split decision

    func testALandscapeWindowSplitsAndAPortraitOneDoesNot() throws {
        let wide = makeRoot(size: CGSize(width: 1024, height: 768))
        XCTAssertEqual(wide.columns?.isWide, true)
        let narrow = makeRoot(size: CGSize(width: 768, height: 1024))
        XCTAssertEqual(narrow.columns?.isWide, false)
        let phone = makeRoot(size: CGSize(width: 390, height: 844), regular: false)
        XCTAssertEqual(phone.columns?.isWide, false)
    }

    func testRotatingAWindowFlipsTheColumnsWithoutLosingTheOpenPage() throws {
        let root = makeRoot(size: CGSize(width: 1024, height: 768))
        let columns = try XCTUnwrap(root.columns)
        let list = try XCTUnwrap(root.shell?.list)
        list.open(FoundationItem(number: 4))
        XCTAssertTrue(LaneBHost.spin(until: { columns.entries.count == 1 && !columns.isTransitioning }))
        let window = try XCTUnwrap(windows.last)
        window.frame = CGRect(x: 0, y: 0, width: 768, height: 1024)
        window.layoutIfNeeded()
        XCTAssertFalse(columns.isWide)
        let navigation = try XCTUnwrap(root.navigation)
        XCTAssertTrue(LaneBHost.spin(until: { navigation.viewControllers.count == 2 }), "the page is pushed on the stack")
        XCTAssertEqual((navigation.topViewController as? FoundationDetailPage)?.title, "Item 4")
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        window.layoutIfNeeded()
        XCTAssertTrue(columns.isWide)
        XCTAssertTrue(LaneBHost.spin(until: { navigation.viewControllers.count == 1 && columns.entries.count == 1 }), "and it comes back as a column")
        XCTAssertEqual(columns.entries.first?.controller.title, "Item 4")
    }

    // MARK: - Opening items

    func testARowOpensBesideTheListWhenWideAndPushesWhenNarrow() throws {
        let wide = makeRoot(size: CGSize(width: 1024, height: 768))
        try XCTUnwrap(wide.shell).list.open(FoundationItem(number: 2))
        let columns = try XCTUnwrap(wide.columns)
        XCTAssertTrue(LaneBHost.spin(until: { columns.entries.count == 1 && !columns.isTransitioning }))
        XCTAssertEqual(wide.columns?.entries.count, 1)
        XCTAssertEqual(wide.navigation?.viewControllers.count, 1)
        XCTAssertEqual(wide.columns?.entries.first?.host.accessibilityIdentifier, FoundationIdentifiers.trailingColumn)

        let narrow = makeRoot(size: CGSize(width: 390, height: 844), regular: false)
        try XCTUnwrap(narrow.shell).list.open(FoundationItem(number: 2))
        LaneBHost.spin(0.6)
        XCTAssertEqual(narrow.columns?.entries.count, 0)
        XCTAssertEqual(narrow.navigation?.viewControllers.count, 2)
    }

    func testTheShellShowsTheColumnsBackOrCloseBesideItsOwnItems() throws {
        let root = makeRoot(size: CGSize(width: 1024, height: 768))
        let shell = try XCTUnwrap(root.shell)
        XCTAssertEqual(shell.navigationItem.rightBarButtonItems?.map(\.accessibilityIdentifier), [FoundationIdentifiers.openSheet])
        shell.list.open(FoundationItem(number: 1))
        let columns = try XCTUnwrap(root.columns)
        XCTAssertTrue(LaneBHost.spin(until: { columns.entries.count == 1 && !columns.isTransitioning }))
        XCTAssertEqual(shell.navigationItem.rightBarButtonItems?.map(\.accessibilityIdentifier),
                       [FoundationIdentifiers.openSheet, FoundationIdentifiers.columnClose])
        XCTAssertEqual(shell.navigationItem.leftBarButtonItems?.map(\.accessibilityIdentifier), [FoundationIdentifiers.menu])
    }

    func testTheListScrollsUnderTheBarAndTheShellLinksIt() throws {
        let root = makeRoot(size: CGSize(width: 390, height: 844), regular: false)
        let shell = try XCTUnwrap(root.shell)
        XCTAssertTrue(shell.contentScrollView === shell.list.collectionView)
        XCTAssertEqual(shell.list.collectionView.accessibilityIdentifier, FoundationIdentifiers.list)
        XCTAssertEqual(shell.list.collectionView.numberOfItems(inSection: 0), FoundationItem.all.count)
    }

    // MARK: - Sheet and menu

    func testTheSheetItemPresentsAPageSheetThroughThePresenter() throws {
        let root = makeRoot(size: CGSize(width: 390, height: 844), regular: false)
        let shell = try XCTUnwrap(root.shell)
        let item = try XCTUnwrap(shell.barItems().trailing.first)
        XCTAssertEqual(item.accessibilityIdentifier, FoundationIdentifiers.openSheet)
        item.primaryAction?.performWithSender(item, target: nil)
        let sheet = try XCTUnwrap(shell.presentedViewController as? FoundationSheetPage)
        XCTAssertEqual(sheet.modalPresentationStyle, .pageSheet)
        XCTAssertNotNil(sheet.sheetPresentationController)
        sheet.loadViewIfNeeded()
        let label = sheet.view.subviews.compactMap { $0 as? UIStackView }.first?.arrangedSubviews
            .first { $0.accessibilityIdentifier == FoundationIdentifiers.sheetStyle } as? UILabel
        XCTAssertEqual(label?.text, "pageSheet")
    }

    func testTheMenuItemOpensTheFlyoutAndASelectionOpensAnItem() throws {
        let root = makeRoot(size: CGSize(width: 390, height: 844), regular: false)
        let shell = try XCTUnwrap(root.shell)
        let menu = try XCTUnwrap(shell.barItems().leading.first)
        XCTAssertEqual(menu.accessibilityIdentifier, FoundationIdentifiers.menu)
        menu.primaryAction?.performWithSender(menu, target: nil)
        let flyout = try XCTUnwrap(root.view.subviews.compactMap { $0 as? FentonFlyoutView }.first)
        XCTAssertTrue(flyout.isOpen)
        XCTAssertTrue(flyout.isBlockingTouches)
        let panel = try XCTUnwrap(flyout.subviews.first { $0.accessibilityIdentifier == FoundationIdentifiers.flyout })
        XCTAssertTrue(panel.accessibilityViewIsModal, "VoiceOver reads only the flyout while it is open")
        XCTAssertFalse(flyout.accessibilityElementsHidden, "and can reach it")
        flyout.close(animated: false)
        XCTAssertFalse(flyout.isOpen)
    }

    func testClosingTheFlyoutThroughItsScrimHidesThePanel() throws {
        let root = makeRoot(size: CGSize(width: 390, height: 844), regular: false)
        let shell = try XCTUnwrap(root.shell)
        let menu = try XCTUnwrap(shell.barItems().leading.first)
        menu.primaryAction?.performWithSender(menu, target: nil)
        let flyout = try XCTUnwrap(root.view.subviews.compactMap { $0 as? FentonFlyoutView }.first)
        LaneBHost.spin(0.6)
        let panel = try XCTUnwrap(flyout.subviews.first { $0.accessibilityIdentifier == FoundationIdentifiers.flyout })
        XCTAssertFalse(panel.isHidden)
        let scrim = try XCTUnwrap(flyout.subviews.first { $0.accessibilityIdentifier == FoundationIdentifiers.flyoutScrim } as? UIControl)
        XCTAssertFalse(scrim.isHidden)
        XCTAssertGreaterThan(scrim.frame.width, 20, "a strip beside the panel on a phone")
        let point = CGPoint(x: scrim.frame.midX, y: scrim.frame.midY)
        XCTAssertTrue(flyout.hitTest(point, with: nil) === scrim, "a touch beside the panel lands on the scrim")
        scrim.sendActions(for: .touchUpInside)
        XCTAssertTrue(LaneBHost.spin(until: { panel.isHidden }), "the panel is hidden once it has gone")
        XCTAssertTrue(flyout.accessibilityElementsHidden, "and its explicit element list is not read while it is closed")
        XCTAssertFalse(flyout.isBlockingTouches)
    }

    func testTheFlyoutSitsOverTheContentAndUnderTheLaunchGround() throws {
        let root = FoundationRootViewController()
        root.setContent(root.makeContent())
        let flyoutIndex = try XCTUnwrap(root.view.subviews.firstIndex { $0 is FentonFlyoutView })
        let contentIndex = try XCTUnwrap(root.view.subviews.firstIndex { $0 === root.content?.view })
        XCTAssertGreaterThan(flyoutIndex, contentIndex, "over the content")
        XCTAssertTrue(root.isShowingLaunchGround)
        XCTAssertGreaterThan(root.view.subviews.count - 1, flyoutIndex, "the launch ground is above")
    }
}
