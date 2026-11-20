#if os(iOS)
import UIKit

/// Posts VoiceOver announcements for changes the screen shows but does not move focus to: a status that appears, a save that
/// starts, an error that arrives (HIG, Accessibility: tell people about visible changes).
///
/// Every announcement goes through this type so a unit test can read what would be spoken with ``sink`` instead of depending on a
/// screen reader.
@MainActor
public enum FentonAnnouncer {
    // MARK: - Test hook

    /// A test hook: when set, receives each announcement instead of the system. Nil in the app.
    ///
    /// The strings it receives: the announced text; `"screenChanged"` or `"screenChanged: <text>"`; `"layoutChanged"` or
    /// `"layoutChanged: <label>"` (the label of the element that takes focus, or the string itself).
    public static var sink: (@MainActor (String) -> Void)?

    // MARK: - Announcing

    /// Speaks `text` after whatever VoiceOver is saying, without moving focus. Empty text is ignored.
    public static func announce(_ text: String) {
        guard !text.isEmpty else { return }
        if let sink { sink(text); return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// Tells VoiceOver the whole screen changed (a new root appeared); focus moves to the first element.
    /// - Parameter text: Spoken first, when the new screen deserves a word.
    public static func screenChanged(announcing text: String? = nil) {
        if let sink { sink("screenChanged" + (text.map { ": " + $0 } ?? "")); return }
        UIAccessibility.post(notification: .screenChanged, argument: text)
    }

    /// Tells VoiceOver part of the screen changed (a panel opened or closed); focus moves to `element` when given.
    /// - Parameter element: The element (or string to speak) that takes focus; nil lets VoiceOver choose.
    public static func layoutChanged(focus element: Any?) {
        if let sink { sink("layoutChanged" + (label(of: element).map { ": " + $0 } ?? "")); return }
        UIAccessibility.post(notification: .layoutChanged, argument: element)
    }

    private static func label(of element: Any?) -> String? {
        if let text = element as? String { return text }
        return (element as? NSObject)?.accessibilityLabel
    }
}
#endif
