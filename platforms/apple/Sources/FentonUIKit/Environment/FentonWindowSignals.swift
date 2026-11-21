#if os(iOS)
import FentonAppleCore
import UIKit

/// What the window knows about a folding phone's hinge and vertical bar, written into one ``FentonWindowEnvironment``.
///
/// The reads come from ``FentonWindowSensors`` (iOS 27.1 SDK APIs; FentonPlatform requires that SDK to build, and an older system
/// reports nothing). The owner (a root or page controller) creates one for its view and calls ``refresh()`` from
/// `viewDidLayoutSubviews`.
///
/// - The hinge in window coordinates, in both poses, written as ``FentonWindowEnvironment/fold``.
/// - Whether the system moved the bar items into a vertical bar, written as ``FentonWindowEnvironment/inVerticalBar``.
/// - System Reduce Motion and Reduce Transparency, written as ``FentonWindowEnvironment/reduceMotion`` and
///   ``FentonWindowEnvironment/reduceTransparency``.
/// - ``FentonHingePresence``: the first hinge ever seen asks the app to re-read the supported orientations.
///
/// Every field is written only when it changes, so observers run once per change and a second ``refresh()`` at the same state
/// writes nothing.
@MainActor
public final class FentonWindowSignals {
    // MARK: - State

    private weak var view: UIView?
    private let environment: FentonWindowEnvironment
    private let presence: FentonHingePresence
    private let sensors: FentonWindowSensors
    private let reflow: FentonReflow?
    private var lastSize: CGSize = .zero
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    // MARK: - Creating

    /// Starts reading the window's signals for `view`.
    /// - Parameters:
    ///   - view: The owner's view; the hinge interaction attaches to it.
    ///   - environment: Where the facts are written.
    ///   - presence: Remembers that this device has a hinge.
    ///   - sensors: The reads; a test injects a Duo.
    ///   - reflow: Animates a posture change; nil changes the fold without animation.
    public init(
        view: UIView,
        environment: FentonWindowEnvironment,
        presence: FentonHingePresence = .shared,
        sensors: FentonWindowSensors = .system,
        reflow: FentonReflow? = FentonReflow()
    ) {
        self.view = view
        self.environment = environment
        self.presence = presence
        self.sensors = sensors
        self.reflow = reflow
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { [weak self] _, update in
                self?.hingeChanged(update.hinge.map { Self.hingeState($0.status) })
            })
        }
        let center = NotificationCenter.default
        for name in [UIAccessibility.reduceMotionStatusDidChangeNotification, UIAccessibility.reduceTransparencyStatusDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    @available(iOS 27.1, *)
    static func hingeState(_ status: UIHinge.Status) -> FentonHingeState {
        switch status {
        case .closed: .closed
        case .fullyOpen: .fullyOpen
        default: .partiallyOpen
        }
    }

    /// The hinge interaction reported a hinge (or none): the first one ever seen asks the app to re-read supported orientations.
    func hingeChanged(_ state: FentonHingeState?) {
        presence.record(hinge: state)
        // A posture change (partly folded <-> flat) may not run a layout pass: read the fold again on the next turn.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: - Reading

    /// Reads the signals and writes what changed; call it from the owner's `viewDidLayoutSubviews` (it also runs after the hinge
    /// interaction and after a change of Reduce Motion or Reduce Transparency).
    ///
    /// A fold change at an unchanged window size (a posture change, not a rotation) reflows with the standard spring
    /// (``FentonReflow``): the write happens here, once, and the animation runs a turn later, outside layout.
    public func refresh() {
        guard let view else { return }
        let fold = Self.fold(in: view, sensors: sensors)
        if fold != environment.fold {
            let posture = environment.fold.hinge != nil && fold.hinge != nil && lastSize == view.bounds.size
            let reduce = sensors.reduceMotion()
            let before = posture ? reflow?.begin(view, reduceMotion: reduce) : nil
            environment.fold = fold
            // Under Reduce Motion with no snapshot to fade there is nothing to animate: the layout changes at once.
            if posture, !reduce || before != nil { reflow?.commit(view, before: before) }
        }
        lastSize = view.bounds.size
        let bar = sensors.hasVerticalBar(view.traitCollection)
        if bar != environment.inVerticalBar {
            environment.inVerticalBar = bar
            presence.record(hinge: nil, hasVerticalBar: bar)
        }
        let motion = sensors.reduceMotion()
        if motion != environment.reduceMotion { environment.reduceMotion = motion }
        let transparency = sensors.reduceTransparency()
        if transparency != environment.reduceTransparency { environment.reduceTransparency = transparency }
    }

    // MARK: - Queries

    /// The window's fold in `view`'s coordinate space: the hinge's division region, and whether it is active (partly folded).
    ///
    /// A flat device reports its (inactive) hinge to the app's own views but not to a window or a presentation's transition view,
    /// so a view with no answer asks the window's root view and converts the frame (a sheet's container needs the hinge for its
    /// placement and the full-height rule).
    public static func fold(in view: UIView, sensors: FentonWindowSensors = .system) -> FentonWindowFold {
        // The app's root view is the one that tells the poses apart: a window (and a presentation's views) report the hinge as
        // active whatever the pose (measured: a flat Duo's window read `isFolding` while the root view read it inactive).
        if let window = view.window ?? (view as? UIWindow), let root = window.rootViewController?.view, root !== view,
           let reported = reportedFold(in: root, sensors: sensors), let frame = reported.hinge {
            return FentonWindowFold(hinge: view.convert(frame, from: root), isFolding: reported.isFolding)
        }
        return reportedFold(in: view, sensors: sensors) ?? .none
    }

    private static func reportedFold(in view: UIView, sensors: FentonWindowSensors) -> FentonWindowFold? {
        if let active = sensors.regions(view, false).first(where: \.isActive) {
            return FentonWindowFold(hinge: active.frame, isFolding: true)
        }
        if let flat = sensors.regions(view, true).first {
            return FentonWindowFold(hinge: flat.frame, isFolding: false)
        }
        return nil
    }

    /// The window's width less the trailing vertical bar (the rail): the space a flat page divides at its midpoint.
    public static func freeWidth(in window: UIWindow, sensors: FentonWindowSensors = .system) -> CGFloat {
        window.bounds.width - railWidth(in: window, sensors: sensors)
    }

    /// The width the system's trailing vertical bar takes; zero without one.
    public static func railWidth(in window: UIWindow, sensors: FentonWindowSensors = .system) -> CGFloat {
        guard sensors.hasVerticalBar(window.traitCollection) else { return 0 }
        return window.safeAreaInsets.right
    }
}
#endif
