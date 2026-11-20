#if os(iOS)
import UIKit

/// The scene delegate an app subclasses to hardcode its own pages: it creates the window, installs a
/// ``FentonRootViewController`` (or the app's subclass of it) and hands the app one hook for its first content.
///
/// ```swift
/// final class SceneDelegate: FentonWindowSceneDelegate {
///     override func makeRootViewController(for scene: UIWindowScene) -> FentonRootViewController {
///         FentonRootViewController(launchGround: .black)
///     }
///     override func makeContentViewController(for scene: UIWindowScene) -> UIViewController? {
///         UINavigationController(rootViewController: HomeViewController())
///     }
/// }
/// ```
///
/// Name the subclass in the scene's `UISceneDelegateClassName`. It holds no session, sign-in or route concept: the app's content
/// and root subclass own those.
@MainActor
open class FentonWindowSceneDelegate: UIResponder, UIWindowSceneDelegate {
    // MARK: - Window

    /// The scene's window, created when the scene connects.
    public var window: UIWindow?

    // MARK: - Hooks

    /// The root of the window. Override to return the app's subclass; the default shows the system background as its launch ground.
    open func makeRootViewController(for scene: UIWindowScene) -> FentonRootViewController {
        FentonRootViewController(launchGround: .systemBackground)
    }

    /// The first content of the window, installed with ``FentonRootViewController/setContent(_:below:above:)`` before the window
    /// is shown. Return nil to install content later.
    open func makeContentViewController(for scene: UIWindowScene) -> UIViewController? { nil }

    // MARK: - UIWindowSceneDelegate

    open func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        installWindow(in: windowScene)
    }

    /// Creates the window, installs the root and the first content, and shows it.
    func installWindow(in windowScene: UIWindowScene) {
        let window = UIWindow(windowScene: windowScene)
        let root = makeRootViewController(for: windowScene)
        if let content = makeContentViewController(for: windowScene) { root.setContent(content) }
        window.rootViewController = root
        self.window = window
        window.makeKeyAndVisible()
    }
}
#endif
