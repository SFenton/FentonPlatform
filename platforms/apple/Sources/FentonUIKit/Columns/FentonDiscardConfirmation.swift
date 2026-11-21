#if os(iOS)
import UIKit

/// The words of a "discard changes" confirmation. The defaults are developer English: FentonPlatform ships no
/// localisation resources, so an app passes its own localised copy.
public struct FentonDiscardCopy: Sendable, Equatable {
    /// The question.
    public var title = "Discard changes?"
    /// The destructive button.
    public var discard = "Discard Changes"
    /// The cancelling button.
    public var keepEditing = "Keep Editing"

    /// Creates the neutral copy.
    public init() {}
}

/// Confirm before a page loses its draft (HIG: Sheets, Modality; Alerts). A page that holds user-generated content is guarded; a
/// selection-only page leaves at once.
@MainActor
public enum FentonDiscardConfirmation {
    /// Shows the confirmation as an action sheet (a popover on iPad, centred on `controller`'s view with no arrow).
    /// - Parameters:
    ///   - controller: Presents the confirmation.
    ///   - copy: The words.
    ///   - onDiscard: Runs after the person confirms and the sheet is gone.
    public static func present(from controller: UIViewController, copy: FentonDiscardCopy = FentonDiscardCopy(),
                               onDiscard: @escaping () -> Void) {
        let dialog = UIAlertController(title: copy.title, message: nil, preferredStyle: .actionSheet)
        dialog.addAction(UIAlertAction(title: copy.discard, style: .destructive) { [weak dialog] _ in
            dialog?.dismiss(animated: true, completion: onDiscard)
        })
        dialog.addAction(UIAlertAction(title: copy.keepEditing, style: .cancel))
        if let popover = dialog.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        controller.present(dialog, animated: true)
    }
}
#endif
