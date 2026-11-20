/// Which orientations the app supports.
///
/// The Info.plist stays the source of truth: a phone is portrait-only, a tablet allows all four. A device that reports a hinge
/// (a folding phone, detected through the hinge or the vertical bar, never by product name) allows every orientation, folded or
/// unfolded.
public enum FentonOrientationPolicy {
    /// Resolves the supported orientations.
    /// - Parameters:
    ///   - declared: The Info.plist declaration for this idiom; empty when missing.
    ///   - hasHinge: A hinge has been observed on this device.
    public static func supported(declared: FentonSupportedOrientations, hasHinge: Bool) -> FentonSupportedOrientations {
        if hasHinge { return .all }
        return declared.isEmpty ? .portrait : declared
    }

    /// The Info.plist keys UIKit reads for an idiom, most specific first.
    public static func infoPlistKeys(isPad: Bool) -> [String] {
        let base = "UISupportedInterfaceOrientations"
        return [base + (isPad ? "~ipad" : "~iphone"), base]
    }

    /// Reads the declaration for an idiom from an Info dictionary; empty when neither key is present.
    public static func declared(in info: [String: Any], isPad: Bool) -> FentonSupportedOrientations {
        for key in infoPlistKeys(isPad: isPad) {
            if let values = info[key] as? [String] { return FentonSupportedOrientations(infoPlistValues: values) }
        }
        return []
    }
}
