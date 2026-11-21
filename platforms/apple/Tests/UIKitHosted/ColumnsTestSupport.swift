#if os(iOS)
import FentonAppleCore
@testable import FentonUIKit
import UIKit
import XCTest

/// The section page above the columns: a bar host that records the column group it is given.
@MainActor
final class ColumnBarHostStub: UIViewController, FentonColumnBarHosting {
    private(set) var groups: [[UIBarButtonItem]] = []
    var items: [UIBarButtonItem] { groups.last ?? [] }

    func setColumnItems(_ items: [UIBarButtonItem]) { groups.append(items) }
}

/// A page whose answer to Back and Close the test sets.
@MainActor
final class GuardedPage: UIViewController, FentonColumnPopGuarding {
    var columnPopDecision = FentonColumnPopDecision.allow
}

/// A page that asks before it leaves: the test keeps the approval and calls it when it likes.
@MainActor
final class ExitRequestingPage: UIViewController, FentonColumnExitRequesting {
    var columnPopDecision = FentonColumnPopDecision.allow
    private(set) var requests: [[UIViewController]] = []
    private(set) var approvals: [() -> Void] = []

    func requestColumnExit(leaving: [UIViewController], completion: @escaping () -> Void) {
        requests.append(leaving)
        approvals.append(completion)
    }
}

/// Columns inside a navigation stack inside a window of a fixed size, with a Duo stand-in feeding the window environment.
@MainActor
final class ColumnsRig {
    let environment = FentonWindowEnvironment()
    let duo = FakeDuo()
    let barHost = ColumnBarHostStub()
    let navigation: UINavigationController
    let root = UIViewController()
    let columns: FentonColumnsViewController
    let window: UIWindow
    private(set) var signals: FentonWindowSignals?
    let size: CGSize

    init(size: CGSize = CGSize(width: 1024, height: 768), wide: Bool = true, appearance: FentonColumnsAppearance = FentonColumnsAppearance()) {
        self.size = size
        root.view.backgroundColor = .systemBackground
        columns = FentonColumnsViewController(root: root, environment: environment, appearance: appearance) {
            let page = UIViewController()
            page.view.accessibilityIdentifier = "placeholder"
            return page
        }
        barHost.loadViewIfNeeded()
        FentonEmbedding.embed(columns, in: barHost)
        navigation = UINavigationController(rootViewController: barHost)
        navigation.isNavigationBarHidden = true
        window = pageTestWindow(navigation, size: size)
        signals = FentonWindowSignals(view: barHost.view, environment: environment, presence: FentonHingePresence(),
                                      sensors: duo.sensors, reflow: nil)
        signals?.refresh()
        if wide { columns.setWide(true) }
        settle()
    }

    /// Lays everything out and lets queued main-queue work and observers run.
    func settle() {
        window.layoutIfNeeded()
        LaneBHost.spin(0.08)
        window.layoutIfNeeded()
    }

    /// Writes the Duo stand-in's state into the environment and lets the columns hear it.
    func refreshSignals() {
        signals?.refresh()
        settle()
    }

    /// A page for the columns, with a name for the failure message.
    func page(_ name: String) -> UIViewController {
        let page = UIViewController()
        page.title = name
        page.view.accessibilityIdentifier = name
        return page
    }

    func tearDown() {
        window.isHidden = true
    }
}
#endif
