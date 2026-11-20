#if os(iOS)
/// A flyout row's presentation, independent of the app's own section catalogue.
public struct FentonFlyoutDestination: Equatable, Sendable {
    /// The identifier ``FentonFlyoutView`` hands the app when the row is chosen.
    public let id: String
    /// The row's visible name.
    public let title: String
    /// An SF Symbol name for the row's icon.
    public let symbol: String
    /// The row's accessibility identifier, for UI tests.
    public let identifier: String
    /// A short count shown at the row's trailing edge (an overdue count); nil shows none.
    public var badge: String?
    /// What VoiceOver speaks instead of ``title`` (for a badge that needs words); nil speaks the title.
    public var spokenLabel: String?

    /// Creates a destination.
    public init(id: String, title: String, symbol: String, identifier: String, badge: String? = nil, spokenLabel: String? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.identifier = identifier
        self.badge = badge
        self.spokenLabel = spokenLabel
    }
}
#endif
