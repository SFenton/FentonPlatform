#if os(iOS)
import Foundation

/// Upgrading over an app that used another scene delegate. iOS persists each `UISceneSession` with its configuration, delegate
/// class included, so a window the earlier app left behind reconnects with that app's own scene delegate, never asking the app
/// delegate for a configuration; the earlier delegate may draw nothing here and the screen stays black. The app adopts such a
/// scene instead.
public enum FentonSceneUpgrade {
    /// Whether a connecting scene's delegate is not the app's own and so must be replaced.
    /// - Parameters:
    ///   - sceneDelegate: The delegate the scene connected with (nil when it has none).
    ///   - ours: The app's scene delegate class.
    public static func needsAdoption(sceneDelegate: AnyObject?, ours: AnyClass) -> Bool {
        guard let object = sceneDelegate as? NSObject else { return true }
        return !object.isKind(of: ours)
    }
}
#endif
