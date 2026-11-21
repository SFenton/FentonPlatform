#if os(iOS)
import FentonAppleCore
import UIKit

/// Presents native page sheets, placed for a folding phone by ``FentonSheetPlacement`` unless the configuration opts out.
@MainActor
public enum FentonSheetPresenter {
    // MARK: - Configuring

    /// Applies native page-sheet mechanics to a controller.
    ///
    /// With ``FentonSheetConfiguration/Placement/duoAware`` the sheet also takes the large detent only where
    /// ``FentonSheetPlacement/fillsHeight(in:presence:sensors:)`` says every sheet fills the height, and is placed by
    /// ``FentonSheetPlacement/place(_:in:presence:sensors:)``.
    /// - Parameters:
    ///   - controller: The controller to present as a sheet.
    ///   - configuration: Detents, grabber, corner radius and placement.
    ///   - view: Any view in the window the sheet will appear in (usually the presenter's); nil reads only the device record.
    ///   - presence: The record that this device has a hinge; a test passes its own.
    ///   - sensors: Where the hinge is read from; a test injects a Duo.
    public static func configure(
        _ controller: UIViewController,
        configuration: FentonSheetConfiguration = .init(),
        in view: UIView? = nil,
        presence: FentonHingePresence = .shared,
        sensors: FentonWindowSensors = .system
    ) {
        controller.modalPresentationStyle = .pageSheet
        guard let sheet = controller.sheetPresentationController else { return }
        let fillsHeight = configuration.placement == .duoAware && FentonSheetPlacement.fillsHeight(in: view, presence: presence, sensors: sensors)
        switch fillsHeight ? .large : configuration.heightPolicy {
        case .medium:
            sheet.detents = [.medium()]
        case .large:
            sheet.detents = [.large()]
        case .mediumAndLarge:
            sheet.detents = [.medium(), .large()]
        }
        sheet.prefersGrabberVisible = configuration.showsGrabber
        sheet.preferredCornerRadius = configuration.cornerRadius
        if configuration.placement == .duoAware { FentonSheetPlacement.place(sheet, in: view, presence: presence, sensors: sensors) }
    }

    // MARK: - Presenting

    /// Configures and presents a native sheet from an existing controller; `presence` and `sensors` are as in
    /// ``configure(_:configuration:in:presence:sensors:)``.
    public static func present(
        _ controller: UIViewController,
        from presenter: UIViewController,
        configuration: FentonSheetConfiguration = .init(),
        animated: Bool = true,
        presence: FentonHingePresence = .shared,
        sensors: FentonWindowSensors = .system,
        completion: (() -> Void)? = nil
    ) {
        configure(controller, configuration: configuration, in: presenter.viewIfLoaded, presence: presence, sensors: sensors)
        presenter.present(controller, animated: animated, completion: completion)
    }
}
#endif
