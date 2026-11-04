#if canImport(UIKit)
import UIKit
import FentonAppleCore

/// Native sheet configuration that leaves application appearance and theme ownership untouched.
@MainActor
public struct FentonSheetConfiguration: Sendable {
    /// The native detent arrangement used by the sheet.
    public var heightPolicy: SheetHeightPolicy
    /// Whether the system grabber is shown for a resizable sheet.
    public var showsGrabber: Bool
    /// An optional native corner radius; nil leaves the system default.
    public var cornerRadius: CGFloat?

    /// Creates configuration without changing the presenting app's appearance.
    public init(
        heightPolicy: SheetHeightPolicy = .mediumAndLarge,
        showsGrabber: Bool = true,
        cornerRadius: CGFloat? = nil
    ) {
        self.heightPolicy = heightPolicy
        self.showsGrabber = showsGrabber
        self.cornerRadius = cornerRadius
    }
}

@MainActor
public enum FentonSheetPresenter {
    /// Applies native page-sheet mechanics to a controller.
    public static func configure(
        _ controller: UIViewController,
        configuration: FentonSheetConfiguration = .init()
    ) {
        controller.modalPresentationStyle = .pageSheet
        guard let sheet = controller.sheetPresentationController else { return }
        switch configuration.heightPolicy {
        case .medium:
            sheet.detents = [.medium()]
        case .large:
            sheet.detents = [.large()]
        case .mediumAndLarge:
            sheet.detents = [.medium(), .large()]
        }
        sheet.prefersGrabberVisible = configuration.showsGrabber
        sheet.preferredCornerRadius = configuration.cornerRadius
    }

    /// Configures and presents a native sheet from an existing controller.
    public static func present(
        _ controller: UIViewController,
        from presenter: UIViewController,
        configuration: FentonSheetConfiguration = .init(),
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        configure(controller, configuration: configuration)
        presenter.present(controller, animated: animated, completion: completion)
    }
}
#endif
