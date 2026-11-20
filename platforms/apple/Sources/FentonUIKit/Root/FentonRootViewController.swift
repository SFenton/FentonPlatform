#if os(iOS)
import FentonAppleCore
import UIKit

/// The root of a window: one content controller over a ground that never blanks, the window's signals, and scene events
/// filtered to this window's scene. An app subclasses it to add its own phases (sign-in, arrival, probes) and hardcodes its pages
/// as content.
///
/// - **No blank frame.** The root's own view is the launch ground colour, and a launch ground view covers the content until
///   ``dismissLaunchGround(animated:)``, which the app calls after the first frame (or leaves to
///   ``dismissesLaunchGroundOnFirstAppearance``). ``setContent(_:below:above:)`` embeds the new content before it removes the old,
///   so the screen never shows the ground between two contents.
/// - **Status bar.** The content controller decides the style and visibility.
/// - **Window signals.** ``environment`` is written by a ``FentonWindowSignals`` bound to this view; pages and columns read it.
/// - **Scene events.** ``onSceneEvent`` hears only this window's scene (a second window or an external display does not call it).
open class FentonRootViewController: UIViewController {
    // MARK: - Properties

    /// The window's facts: fold, vertical bar, Reduce Motion, Reduce Transparency. Written by the root's signals.
    public let environment = FentonWindowEnvironment()

    /// Called on the main actor for this window's scene lifecycle changes.
    public var onSceneEvent: ((FentonSceneEvent) -> Void)?

    /// The content controller, if any.
    public private(set) var content: UIViewController?

    /// Whether the root dismisses the launch ground itself once its first appearance has had a frame. An app that waits for its
    /// own first content (a session, a snapshot) sets this to false and calls ``dismissLaunchGround(animated:)`` itself.
    public var dismissesLaunchGroundOnFirstAppearance = true

    /// Motion values for the launch ground's fade.
    public var motion = FentonMotion()

    private let launchGroundColor: UIColor
    private let presence: FentonHingePresence
    private let sensors: FentonWindowSensors
    private var launchGround: UIView?
    private var signals: FentonWindowSignals?
    private var hasAppeared = false
    nonisolated(unsafe) private var sceneObservers: [NSObjectProtocol] = []

    // MARK: - Creating

    /// Creates a root over `launchGround`.
    /// - Parameters:
    ///   - launchGround: The colour under and over the content until the first frame (match the launch screen).
    ///   - presence: Remembers that this device has a hinge.
    ///   - sensors: The hinge and accessibility reads; a test injects a Duo.
    public init(launchGround: UIColor, presence: FentonHingePresence = .shared, sensors: FentonWindowSensors = .system) {
        launchGroundColor = launchGround
        self.presence = presence
        self.sensors = sensors
        super.init(nibName: nil, bundle: nil)
        FentonOrientationSupport.install(on: presence)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        sceneObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - View lifecycle

    open override func viewDidLoad() {
        super.viewDidLoad()
        // One ground under the content and the launch ground over it.
        view.backgroundColor = launchGroundColor
        signals = FentonWindowSignals(view: view, environment: environment, presence: presence, sensors: sensors)
        installLaunchGround()
        observeScene()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        signals?.refresh()
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAppeared else { return }
        hasAppeared = true
        guard dismissesLaunchGroundOnFirstAppearance else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.dismissLaunchGround(animated: true)
        }
    }

    // MARK: - Orientation

    /// The orientations the window supports: the Info.plist declaration for the idiom, and every orientation once a hinge has been
    /// seen (``FentonOrientationSupport``). The first hinge asks the scenes to read this again. Override to add the app's own rule.
    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        FentonOrientationSupport.mask(for: viewIfLoaded?.window, presence: presence)
    }

    // MARK: - Status bar

    open override var childForStatusBarStyle: UIViewController? { content }
    open override var childForStatusBarHidden: UIViewController? { content }

    // MARK: - Content

    /// Installs `controller` as the window's content, replacing the previous content.
    ///
    /// The new content is embedded before the old is removed (no frame between them shows only the ground), and the launch ground,
    /// while it is up, stays over both.
    /// - Parameters:
    ///   - controller: The new content; nil removes the content.
    ///   - below: A view of this root to put the content under (an overlay that must stay on top).
    ///   - above: A view of this root to put the content over; ignored when `below` is given.
    public func setContent(_ controller: UIViewController?, below: UIView? = nil, above: UIView? = nil) {
        loadViewIfNeeded()
        let previous = content
        content = controller
        if let controller, controller !== previous {
            let position: FentonEmbedding.Position
            if let below { position = .below(below) } else if let above { position = .above(above) } else { position = .back }
            FentonEmbedding.embed(controller, in: self, position: position)
        }
        if let previous, previous !== controller { FentonEmbedding.remove(previous) }
        if let launchGround { view.bringSubviewToFront(launchGround) }
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Launch ground

    /// Whether the launch ground is still over the content.
    public var isShowingLaunchGround: Bool { launchGround != nil }

    /// The first frame is up: lets the launch ground go. Never blanks: the ground leaves by fading away from a full-bleed layer
    /// over content that is already in place. A second call does nothing.
    /// - Parameter animated: Fade out over ``FentonMotion/quick``; false removes it at once.
    public func dismissLaunchGround(animated: Bool) {
        guard let ground = launchGround else { return }
        launchGround = nil
        guard animated else {
            ground.removeFromSuperview()
            return
        }
        UIView.animate(withDuration: motion.quick, delay: 0, options: .curveEaseOut, animations: { ground.alpha = 0 },
                       completion: { _ in ground.removeFromSuperview() })
    }

    private func installLaunchGround() {
        let ground = UIView(frame: view.bounds)
        ground.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        ground.backgroundColor = launchGroundColor
        ground.isUserInteractionEnabled = false
        ground.accessibilityElementsHidden = true
        view.addSubview(ground)
        launchGround = ground
    }

    // MARK: - Scene events

    private func observeScene() {
        let center = NotificationCenter.default
        let events: [(Notification.Name, FentonSceneEvent)] = [
            (UIScene.didActivateNotification, .didActivate),
            (UIScene.willDeactivateNotification, .willDeactivate),
            (UIScene.didEnterBackgroundNotification, .didEnterBackground)
        ]
        for (name, event) in events {
            sceneObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let scene = note.object as? UIScene
                MainActor.assumeIsolated {
                    guard let self, self.isOwnScene(scene) else { return }
                    self.onSceneEvent?(event)
                }
            })
        }
    }

    /// Whether `scene` is the scene this root's window is in.
    func isOwnScene(_ scene: UIScene?) -> Bool {
        guard let scene, let own = view.window?.windowScene else { return false }
        return scene === own
    }
}
#endif
