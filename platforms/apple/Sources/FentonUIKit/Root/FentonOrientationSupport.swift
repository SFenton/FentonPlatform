#if os(iOS)
import FentonAppleCore
import UIKit

/// The UIKit side of ``FentonOrientationPolicy``: turns the policy's answer into a `UIInterfaceOrientationMask`, reads the
/// Info.plist declaration, and asks scenes to re-read the answer once a hinge has been seen.
///
/// **Why scenes must be asked.** UIKit reads `supportedInterfaceOrientations` when a controller appears or rotates. A folding phone
/// is first known to be one only after its first hinge reading, which can come after the first read, so the first hinge calls
/// `setNeedsUpdateOfSupportedInterfaceOrientations()` on every window's root controller. ``FentonRootViewController`` installs this
/// on its ``FentonHingePresence`` and answers through ``mask(for:presence:info:)``.
///
/// **A root controller can only narrow.** UIKit intersects the root's answer with the app's: the Info.plist declaration, or the
/// app delegate's `application(_:supportedInterfaceOrientationsFor:)` when it implements one. A phone that declares portrait only
/// therefore stays portrait however the root answers. To open every orientation after a hinge, the app delegate must answer too,
/// from the same ``FentonHingePresence``: subclass ``FentonApplicationDelegate``, or call ``mask(for:presence:info:)`` from its own
/// `supportedInterfaceOrientationsFor`.
public enum FentonOrientationSupport {
    // MARK: - Mapping

    /// The UIKit mask for `orientations`.
    public static func mask(for orientations: FentonSupportedOrientations) -> UIInterfaceOrientationMask {
        var mask: UIInterfaceOrientationMask = []
        if orientations.contains(.portrait) { mask.insert(.portrait) }
        if orientations.contains(.portraitUpsideDown) { mask.insert(.portraitUpsideDown) }
        if orientations.contains(.landscapeLeft) { mask.insert(.landscapeLeft) }
        if orientations.contains(.landscapeRight) { mask.insert(.landscapeRight) }
        return mask
    }

    /// Every orientation once a hinge has been observed, else the Info.plist declaration for the idiom (portrait when it declares
    /// none).
    /// - Parameters:
    ///   - window: The window whose idiom picks the declaration; nil reads the device's idiom.
    ///   - presence: Whether a hinge has been seen.
    ///   - info: The Info dictionary to read; nil reads the main bundle's.
    @MainActor
    public static func mask(for window: UIWindow?, presence: FentonHingePresence = .shared, info: [String: Any]? = nil) -> UIInterfaceOrientationMask {
        let idiom = window?.traitCollection.userInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom
        let declared = FentonOrientationPolicy.declared(in: info ?? Bundle.main.infoDictionary ?? [:], isPad: idiom == .pad)
        return mask(for: FentonOrientationPolicy.supported(declared: declared, hasHinge: presence.hasHinge))
    }

    // MARK: - First hinge

    /// The windows of every connected window scene.
    @MainActor
    public static func connectedWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    }

    /// Asks each window's root controller to re-read its supported orientations.
    /// - Parameter windows: The windows to ask; defaults to every connected scene's.
    @MainActor
    public static func requestUpdate(windows: @MainActor () -> [UIWindow] = FentonOrientationSupport.connectedWindows) {
        for window in windows() { window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
    }

    /// Makes the first hinge on `presence` call ``requestUpdate(windows:)``, keeping whatever `onFirstHinge` already did. A second
    /// call for the same presence does nothing.
    /// - Parameters:
    ///   - presence: The record to watch.
    ///   - windows: The windows to ask; defaults to every connected scene's.
    @MainActor
    public static func install(on presence: FentonHingePresence, windows: @escaping @MainActor () -> [UIWindow] = FentonOrientationSupport.connectedWindows) {
        guard !installed.contains(presence) else { return }
        installed.add(presence)
        let previous = presence.onFirstHinge
        presence.onFirstHinge = {
            previous()
            requestUpdate(windows: windows)
        }
    }

    @MainActor private static let installed = NSHashTable<FentonHingePresence>.weakObjects()
}
#endif
