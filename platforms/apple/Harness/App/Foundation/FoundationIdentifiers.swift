/// Accessibility identifiers of the foundation fixture: the names the journeys and the hosted tests look elements up by.
enum FoundationIdentifiers {
    /// The launch argument that routes the harness to the foundation fixture.
    static let launchArgument = "--foundation"

    static let list = "foundation.list"
    static let menu = "foundation.menu"
    static let openSheet = "foundation.open-sheet"
    static let emptyDetail = "foundation.empty"
    static let detailTitle = "foundation.detail.title"
    static let detailBody = "foundation.detail.body"
    static let detailScroll = "foundation.detail"
    static let sheetTitle = "foundation.sheet.title"
    static let sheetStyle = "foundation.sheet.style"
    static let sheetClose = "foundation.sheet.close"
    static let trailingColumn = "split.trailing"
    static let flyout = "flyout"
    static let flyoutScrim = "flyout.scrim"
    static let columnClose = "column.close"
    static let columnBack = "column.back"

    /// The identifier of the list row for `item`.
    static func row(_ item: Int) -> String { "foundation.row.\(item)" }

    /// The identifier of a flyout destination.
    static func destination(_ id: String) -> String { "foundation.flyout.\(id)" }
}
