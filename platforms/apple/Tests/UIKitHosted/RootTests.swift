#if os(iOS)
import FentonAppleCore
@testable import FentonUIKit
import UIKit
import XCTest

@MainActor
final class RootTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    private func makeRoot(sensors: FentonWindowSensors = FakeDuo().sensors) -> FentonRootViewController {
        let root = FentonRootViewController(launchGround: .black, presence: FentonHingePresence(), sensors: sensors)
        root.dismissesLaunchGroundOnFirstAppearance = false
        return root
    }

    private func show(_ root: FentonRootViewController) throws {
        windows.append(try LaneBHost.window(showing: root))
    }

    // MARK: Content and the launch ground

    func testSetContentEmbedsAsAChildAndTheLaunchGroundStaysOverIt() throws {
        let root = makeRoot()
        let page = UIViewController()
        root.setContent(page)
        XCTAssertTrue(page.parent === root)
        XCTAssertTrue(root.content === page)
        XCTAssertTrue(page.view.superview === root.view)
        XCTAssertTrue(root.isShowingLaunchGround)
        XCTAssertEqual(root.view.backgroundColor, .black)
        XCTAssertNotEqual(root.view.subviews.last, page.view, "the ground is over the content")
    }

    func testReplacingContentNeverShowsOnlyTheGroundAndTheLaunchGroundStaysUntilDismissed() throws {
        let root = makeRoot()
        let first = UIViewController()
        let second = UIViewController()
        root.setContent(first)
        try show(root)
        root.setContent(second)

        XCTAssertNil(first.parent)
        XCTAssertNil(first.view.superview)
        XCTAssertTrue(second.view.superview === root.view, "the new content is in before the old is out")
        XCTAssertTrue(root.isShowingLaunchGround, "the ground stays until dismissLaunchGround")
        let ground = try XCTUnwrap(root.view.subviews.last)
        XCTAssertEqual(ground.backgroundColor, .black)
        XCTAssertFalse(ground.isUserInteractionEnabled)
        XCTAssertTrue(ground.accessibilityElementsHidden)

        root.dismissLaunchGround(animated: false)
        XCTAssertFalse(root.isShowingLaunchGround)
        XCTAssertNil(ground.superview)
        XCTAssertTrue(second.view.superview === root.view, "dismissing the ground reveals content already in place")
        root.dismissLaunchGround(animated: false)
        root.dismissLaunchGround(animated: true)
    }

    func testAnimatedDismissFadesTheGroundThenRemovesIt() throws {
        let root = makeRoot()
        root.setContent(UIViewController())
        try show(root)
        let ground = try XCTUnwrap(root.view.subviews.last)
        root.dismissLaunchGround(animated: true)
        XCTAssertFalse(root.isShowingLaunchGround)
        XCTAssertTrue(LaneBHost.spin(until: { ground.superview == nil }))
    }

    func testTheRootDismissesTheGroundAfterItsFirstAppearanceUnlessTheAppTakesOver() throws {
        let root = FentonRootViewController(launchGround: .black, presence: FentonHingePresence(), sensors: FakeDuo().sensors)
        root.setContent(UIViewController())
        try show(root)
        XCTAssertTrue(LaneBHost.spin(until: { !root.isShowingLaunchGround }))

        let held = makeRoot()
        held.setContent(UIViewController())
        try show(held)
        LaneBHost.spin(0.3)
        XCTAssertTrue(held.isShowingLaunchGround, "an app that waits for its own first content keeps the ground")
    }

    func testSettingNilContentRemovesIt() {
        let root = makeRoot()
        let page = UIViewController()
        root.setContent(page)
        root.setContent(nil)
        XCTAssertNil(page.parent)
        XCTAssertNil(root.content)
    }

    func testBelowAndAbovePlaceTheContentRelativeToAnOverlay() throws {
        let root = makeRoot()
        root.loadViewIfNeeded()
        let overlay = UIView()
        root.view.insertSubview(overlay, at: 0)
        let under = UIViewController()
        root.setContent(under, below: overlay)
        let subviews = root.view.subviews
        XCTAssertLessThan(try XCTUnwrap(subviews.firstIndex(of: under.view)), try XCTUnwrap(subviews.firstIndex(of: overlay)))

        let over = UIViewController()
        root.setContent(over, above: overlay)
        let again = root.view.subviews
        XCTAssertGreaterThan(try XCTUnwrap(again.firstIndex(of: over.view)), try XCTUnwrap(again.firstIndex(of: overlay)))
    }

    // MARK: Status bar

    private final class LightPage: UIViewController {
        override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
        override var prefersStatusBarHidden: Bool { true }
    }

    func testStatusBarStyleAndVisibilityComeFromTheContent() {
        let root = makeRoot()
        XCTAssertNil(root.childForStatusBarStyle)
        let page = LightPage()
        root.setContent(page)
        XCTAssertTrue(root.childForStatusBarStyle === page)
        XCTAssertTrue(root.childForStatusBarHidden === page)
        root.setContent(nil)
        XCTAssertNil(root.childForStatusBarStyle)
    }

    // MARK: Signals

    func testTheRootWritesItsEnvironmentFromTheInjectedSensors() throws {
        let duo = FakeDuo()
        let root = makeRoot(sensors: duo.sensors)
        try show(root)
        duo.partlyFolded(in: root.view.bounds.size)
        root.view.setNeedsLayout()
        root.view.layoutIfNeeded()
        XCTAssertTrue(root.environment.fold.isFolding)
        XCTAssertEqual(root.environment.band, duo.hinge)
    }

    // MARK: Scene events

    func testSceneEventsReachOnlyTheOwnScene() throws {
        let root = makeRoot()
        try show(root)
        let scene = try XCTUnwrap(root.view.window?.windowScene)
        var heard: [FentonSceneEvent] = []
        root.onSceneEvent = { heard.append($0) }

        let names: [(Notification.Name, FentonSceneEvent)] = [
            (UIScene.didActivateNotification, .didActivate),
            (UIScene.willDeactivateNotification, .willDeactivate),
            (UIScene.didEnterBackgroundNotification, .didEnterBackground)
        ]
        for (name, _) in names {
            NotificationCenter.default.post(name: name, object: nil)
        }
        LaneBHost.spin(0.1)
        XCTAssertTrue(heard.isEmpty, "a notification from no scene is not ours")

        for (name, _) in names { NotificationCenter.default.post(name: name, object: scene) }
        XCTAssertTrue(LaneBHost.spin(until: { heard.count == 3 }))
        XCTAssertEqual(heard.map { "\($0)" }, names.map { "\($0.1)" })
        XCTAssertTrue(root.isOwnScene(scene))
        XCTAssertFalse(root.isOwnScene(nil))
    }

    func testARootNotInAWindowOwnsNoScene() throws {
        let root = makeRoot()
        root.loadViewIfNeeded()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first)
        XCTAssertFalse(root.isOwnScene(scene))
    }

    // MARK: Scene delegate

    private final class AppSceneDelegate: FentonWindowSceneDelegate {
        let page = UIViewController()
        override func makeContentViewController(for scene: UIWindowScene) -> UIViewController? { page }
    }

    func testTheSceneDelegateInstallsTheRootAndTheAppsFirstContent() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.keyWindow
        let delegate = AppSceneDelegate()
        delegate.installWindow(in: scene)
        defer {
            delegate.window?.isHidden = true
            previousKey?.makeKey()
        }
        let root = try XCTUnwrap(delegate.window?.rootViewController as? FentonRootViewController)
        XCTAssertTrue(root.content === delegate.page)
        XCTAssertTrue(delegate.window?.isKeyWindow ?? false)
    }

    private final class PlainSceneDelegate: FentonWindowSceneDelegate {}

    func testTheDefaultSceneDelegateShowsARootWithNoContent() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.keyWindow
        let delegate = PlainSceneDelegate()
        delegate.installWindow(in: scene)
        defer {
            delegate.window?.isHidden = true
            previousKey?.makeKey()
        }
        let root = try XCTUnwrap(delegate.window?.rootViewController as? FentonRootViewController)
        XCTAssertNil(root.content)
    }

    // MARK: Scene upgrade

    private final class Ours: NSObject {}
    private final class Foreign: NSObject {}

    func testForeignOrMissingDelegateIsAdoptedAndOwnIsLeftAlone() {
        XCTAssertTrue(FentonSceneUpgrade.needsAdoption(sceneDelegate: Foreign(), ours: Ours.self))
        XCTAssertTrue(FentonSceneUpgrade.needsAdoption(sceneDelegate: nil, ours: Ours.self))
        XCTAssertFalse(FentonSceneUpgrade.needsAdoption(sceneDelegate: Ours(), ours: Ours.self))
    }
}
#endif
