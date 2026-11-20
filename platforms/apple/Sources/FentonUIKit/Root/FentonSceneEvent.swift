#if os(iOS)
/// A scene lifecycle change of the window a ``FentonRootViewController`` is in.
public enum FentonSceneEvent: Sendable {
    /// The scene became active (foreground, in focus).
    case didActivate
    /// The scene will stop being active (an interruption, or on its way to the background).
    case willDeactivate
    /// The scene entered the background.
    case didEnterBackground
}
#endif
