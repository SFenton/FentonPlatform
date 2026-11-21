/// Interface orientations, platform-neutral so the policy compiles and tests on the macOS host.
public struct FentonSupportedOrientations: OptionSet, Sendable, Hashable {
    /// The raw bits.
    public let rawValue: Int

    /// Creates a set from raw bits.
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Portrait.
    public static let portrait = FentonSupportedOrientations(rawValue: 1 << 0)
    /// Portrait, upside down.
    public static let portraitUpsideDown = FentonSupportedOrientations(rawValue: 1 << 1)
    /// Landscape, home indicator on the left.
    public static let landscapeLeft = FentonSupportedOrientations(rawValue: 1 << 2)
    /// Landscape, home indicator on the right.
    public static let landscapeRight = FentonSupportedOrientations(rawValue: 1 << 3)
    /// All four orientations.
    public static let all: FentonSupportedOrientations = [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]

    /// Parses an Info.plist `UISupportedInterfaceOrientations` array; unknown names are ignored.
    public init(infoPlistValues: [String]) {
        var result: FentonSupportedOrientations = []
        for value in infoPlistValues {
            switch value {
            case "UIInterfaceOrientationPortrait": result.insert(.portrait)
            case "UIInterfaceOrientationPortraitUpsideDown": result.insert(.portraitUpsideDown)
            case "UIInterfaceOrientationLandscapeLeft": result.insert(.landscapeLeft)
            case "UIInterfaceOrientationLandscapeRight": result.insert(.landscapeRight)
            default: break
            }
        }
        self = result
    }
}
