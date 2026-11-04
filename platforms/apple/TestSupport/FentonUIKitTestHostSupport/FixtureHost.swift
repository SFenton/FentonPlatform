#if canImport(UIKit)
import UIKit

/// Debug-only in-process fixture hosting. It contains no test listener or IPC channel.
@MainActor
public final class FentonUIKitFixtureHost {
    public private(set) var generation = 0
    public let window: UIWindow

    public init(window: UIWindow = UIWindow(frame: UIScreen.main.bounds)) {
        self.window = window
    }

    public func show(_ controller: UIViewController) {
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    public func reset() {
        generation += 1
        window.rootViewController?.dismiss(animated: false)
        window.rootViewController = nil
    }
}
#endif
