import FentonUIKit
import UIKit

/// How an app hardcodes its pages on FentonPlatform: a `FentonWindowSceneDelegate` subclass that names its root and hands over its
/// first content. The harness's `SceneDelegate` routes here when launched with `--foundation`.
final class FoundationSceneDelegate: FentonWindowSceneDelegate {
    private var root: FoundationRootViewController?

    override func makeRootViewController(for scene: UIWindowScene) -> FentonRootViewController {
        let root = FoundationRootViewController()
        self.root = root
        return root
    }

    override func makeContentViewController(for scene: UIWindowScene) -> UIViewController? {
        root?.makeContent()
    }
}
