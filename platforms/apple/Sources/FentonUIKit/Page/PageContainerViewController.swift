#if canImport(UIKit)
import UIKit
import FentonAppleTelemetry

/// A page host with one safe-area owner and explicit scroll/accessory registration.
@MainActor
public final class FentonPageContainerViewController: UIViewController {
    /// The content container. Consumers normally use ``embed(_:mainScrollView:)``.
    public var contentView: UIView { containmentView.contentView }
    private let containmentView = FentonContentContainmentView()
    private var contentViewController: UIViewController?
    private var didMeasureLayout = false
    private let telemetry: FentonTelemetry?

    /// Creates a page host without taking ownership of application theme or chrome.
    public init(telemetry: FentonTelemetry? = nil) {
        self.telemetry = telemetry
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    public override func loadView() {
        view = containmentView
    }

    /// Embeds one feature controller and optionally registers its primary scroll view.
    public func embed(_ controller: UIViewController, mainScrollView: UIScrollView? = nil) {
        containmentView.unregisterMainScrollView()
        if let existing = contentViewController {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
        }
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        contentViewController = controller
        if let mainScrollView {
            registerMainScrollView(mainScrollView)
        }
    }

    /// Registers the scroll view whose content and indicators need accessory clearance.
    public func registerMainScrollView(_ scrollView: UIScrollView) {
        containmentView.registerMainScrollView(scrollView)
    }

    /// Unregisters a scroll view and restores its original UIKit inset behavior.
    public func unregisterMainScrollView(_ scrollView: UIScrollView? = nil) {
        containmentView.unregisterMainScrollView(scrollView)
    }

    /// Adds a bottom accessory while keeping the page's safe-area and scroll ownership centralized.
    public func registerAccessoryView(_ accessory: UIView, clearance: CGFloat = 12) {
        containmentView.registerAccessoryView(accessory, clearance: clearance)
    }

    /// Removes the registered accessory and restores the page's original bottom inset.
    public func clearAccessoryView() {
        containmentView.clearAccessoryView()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didMeasureLayout {
            didMeasureLayout = true
            telemetry?.measure("first-layout") {}
        }
        containmentView.setNeedsLayout()
    }
}

/// A native split container that preserves child controller identity.
@MainActor
public final class FentonPaneContainerViewController: UISplitViewController {
    /// Creates a native two-column split while preserving both child controllers.
    public init(primary: UIViewController, secondary: UIViewController) {
        super.init(style: .doubleColumn)
        setViewController(primary, for: .primary)
        setViewController(secondary, for: .secondary)
        preferredSplitBehavior = .tile
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
#endif
