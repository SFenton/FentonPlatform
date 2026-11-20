#if os(iOS)
import UIKit

/// Debug-only in-process fixture hosting. It contains no test listener or IPC channel.
@MainActor
public final class FentonUIKitFixtureHost {
    /// How many times ``reset()`` has run.
    public private(set) var generation = 0
    /// The window the fixtures are shown in.
    public let window: UIWindow

    /// Hosts fixtures in `window`.
    public init(window: UIWindow) {
        self.window = window
    }

    /// Hosts fixtures in a new window of `windowScene`, or of the app's first connected window scene when nil.
    ///
    /// A window belongs to a scene (`UIScreen.main` is deprecated): the window is created in the scene's own coordinate space.
    /// With no connected scene (a unit test outside an app) the window has no frame until a scene adopts it.
    public init(windowScene: UIWindowScene? = nil) {
        let scene = windowScene ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
    }

    /// Shows `controller` as the window's root and makes the window key.
    public func show(_ controller: UIViewController) {
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    /// Dismisses everything and empties the window.
    public func reset() {
        generation += 1
        window.rootViewController?.dismiss(animated: false)
        window.rootViewController = nil
    }
}
#endif
