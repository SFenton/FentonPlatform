/// One hardcoded row of the fixture. An app that adopts FentonPlatform writes its pages like this: plain values in the binary of the
/// app, and the foundation draws, moves and sizes them.
struct FoundationItem: Hashable {
    let number: Int

    var title: String { "Item \(number)" }

    var summary: String {
        "Item \(number) is a page of the foundation fixture. It opens beside the list when the window is wide enough to split, and is "
            + "pushed on the navigation stack when it is not."
    }

    /// The fixture's rows: enough to scroll on any device.
    static let all = (0..<60).map(FoundationItem.init(number:))
}
