#if canImport(UIKit)
import UIKit

/// An embeddable controller host for feature pages that need stable identity.
@MainActor
public final class FentonViewControllerHost: UIViewController {
    private var hosted: UIViewController?

    /// Creates an embeddable host with an optional initial controller.
    public init(_ controller: UIViewController? = nil) {
        hosted = controller
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Replaces the hosted controller without replacing this host's identity.
    public func setHostedController(_ controller: UIViewController?) {
        guard hosted !== controller else { return }
        if let current = hosted {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        hosted = controller
        guard let controller, isViewLoaded else { return }
        embed(controller)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        if let hosted { embed(hosted) }
    }

    private func embed(_ controller: UIViewController) {
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
    }
}
#endif
