import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var foundation: FoundationSceneDelegate?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        if ProcessInfo.processInfo.arguments.contains(FoundationIdentifiers.launchArgument) {
            let foundation = FoundationSceneDelegate()
            foundation.scene(scene, willConnectTo: session, options: connectionOptions)
            self.foundation = foundation
            window = foundation.window
            return
        }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: HarnessRootViewController())
        self.window = window
        window.makeKeyAndVisible()
    }
}
