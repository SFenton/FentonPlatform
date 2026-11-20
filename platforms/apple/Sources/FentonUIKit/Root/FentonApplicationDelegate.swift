#if os(iOS)
import FentonAppleCore
import UIKit

/// An application delegate base class that answers `application(_:supportedInterfaceOrientationsFor:)` from a
/// ``FentonHingePresence``, so the app's orientations open up once a hinge has been seen.
///
/// UIKit intersects the root controller's answer with the application's, so ``FentonRootViewController`` alone can only narrow what
/// the Info.plist allows. This class is the application's half: the Info.plist declaration for the idiom until a hinge is seen,
/// every orientation after (``FentonOrientationSupport/mask(for:presence:info:)``). An app that needs its own delegate base calls
/// that function from its own `supportedInterfaceOrientationsFor` instead; the answer is the same.
///
/// Subclass it, mark the subclass `@main`, and pass the same ``presence`` to the root controller when it is not
/// ``FentonHingePresence/shared``.
open class FentonApplicationDelegate: UIResponder, UIApplicationDelegate {
    // MARK: - Presence

    /// The record of whether a hinge has been seen; the root controller must use the same one. Defaults to the shared instance.
    @MainActor
    open var presence: FentonHingePresence { .shared }

    // MARK: - Orientation

    /// The orientations the app allows for `window`; also arranges for the first hinge to ask the scenes to read this again.
    @MainActor
    open func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        FentonOrientationSupport.install(on: presence)
        return FentonOrientationSupport.mask(for: window, presence: presence)
    }
}
#endif
