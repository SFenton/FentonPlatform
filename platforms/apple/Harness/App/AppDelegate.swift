import FentonUIKit
import UIKit

@main
/// Answers orientations from the shared hinge presence, as the foundation fixture's root does (``FentonApplicationDelegate``).
final class AppDelegate: FentonApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
