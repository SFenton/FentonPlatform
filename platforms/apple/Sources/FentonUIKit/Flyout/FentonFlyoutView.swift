#if os(iOS)
import FentonAppleCore
import UIKit

/// The navigation panel behind a menu button: an overlay that slides in from the leading edge over a full-window scrim. It never
/// pushes or resizes the content. Optional: an app with its own navigation does not use it.
///
/// Closes on a destination, a scrim tap, Escape or the VoiceOver escape gesture. Three layers, back to front: a touch shield over
/// the whole window (so nothing under the panel answers while it is open or still sliding away), the dimming scrim with its close
/// target beside the panel, and the panel with its heading and one row per destination. While open the panel is
/// `accessibilityViewIsModal`; opening moves VoiceOver to the heading, and closing announces the layout change (focus returns to
/// ``returnFocusElement``).
///
/// The view asks to be closed (`onDismiss`) and the owner calls ``close(animated:)``; the owner's state stays the truth.
public final class FentonFlyoutView: UIView {
    // MARK: - Properties

    /// The heading's text. Copy belongs to the app: localise it.
    public var title: String {
        get { panel.title }
        set { panel.title = newValue }
    }

    /// The spoken label of the close button and the scrim target. Copy belongs to the app: localise it.
    public var closeLabel: String = "Close Navigation" {
        didSet {
            panel.closeLabel = closeLabel
            closeTarget.accessibilityLabel = closeLabel
        }
    }

    /// The element VoiceOver focuses when the flyout closes (the menu button that opened it); nil lets VoiceOver choose.
    public weak var returnFocusElement: AnyObject?

    /// Motion values for the open and close animations.
    public var motion = FentonMotion()

    /// Whether the overlay answers touches: it is open, or still sliding away.
    public var isBlockingTouches: Bool { isOpen || isSettling }

    /// Whether the flyout is open (or opening).
    public private(set) var isOpen = false

    private let environment: FentonWindowEnvironment
    private let onDismiss: () -> Void
    private let shield = UIView()
    private let dim = UIView()
    private let closeTarget = UIButton(type: .custom)
    private let panel = FentonFlyoutPanel()
    private var isSettling = false
    private var settleToken = 0

    // MARK: - Creating

    /// Creates a closed flyout.
    /// - Parameters:
    ///   - environment: Supplies Reduce Motion.
    ///   - onDismiss: Called when a scrim tap, Escape, the close button or the VoiceOver escape asks to close.
    ///   - onSelect: Called with a destination's `id` when its row is chosen.
    public init(environment: FentonWindowEnvironment, onDismiss: @escaping () -> Void, onSelect: @escaping (String) -> Void) {
        self.environment = environment
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        backgroundColor = .clear
        shield.backgroundColor = .clear
        shield.isAccessibilityElement = false
        shield.accessibilityElementsHidden = true
        shield.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTapped)))
        addSubview(shield)
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        dim.isUserInteractionEnabled = false
        dim.accessibilityElementsHidden = true
        addSubview(dim)
        closeTarget.accessibilityLabel = closeLabel
        closeTarget.accessibilityIdentifier = "flyout.scrim"
        closeTarget.addAction(UIAction { [weak self] _ in self?.onDismiss() }, for: .touchUpInside)
        addSubview(closeTarget)
        panel.accessibilityIdentifier = "flyout"
        panel.onEscape = { [weak self] in self?.onDismiss() }
        panel.onClose = { [weak self] in self?.onDismiss() }
        panel.onSelect = onSelect
        addSubview(panel)
        // The panel's rows come first for VoiceOver; the close target is reachable after them.
        accessibilityElements = [panel, closeTarget]
        // An explicit `accessibilityElements` list is read whatever `isHidden` says (measured in the harness: the closed panel's rows
        // were still reachable off screen), so the closed flyout hides its elements itself.
        accessibilityElementsHidden = true
        shield.isHidden = true
        dim.alpha = 0
        closeTarget.isHidden = true
        panel.isHidden = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: FentonFlyoutView, _) in
            view.panel.contentSizeChanged()
            view.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Destinations

    /// Applies destinations without reconstructing surviving rows or restarting an in-progress animation.
    /// - Parameters:
    ///   - items: The rows, in order.
    ///   - selected: The `id` of the current destination, shown on a tint.
    public func setDestinations(_ items: [FentonFlyoutDestination], selected: String?) {
        panel.update(destinations: items, selection: selected)
    }

    @objc private func dismissTapped() { onDismiss() }

    // MARK: - Touches

    /// The overlay is invisible to touches except while the flyout is open or settling closed.
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isBlockingTouches else { return nil }
        return super.hitTest(point, with: event)
    }

    // MARK: - Layout

    private var panelWidth: CGFloat {
        let preferred = UIFontMetrics(forTextStyle: .body).scaledValue(for: 300, compatibleWith: traitCollection)
        return Self.panelWidth(preferred: preferred, available: bounds.width)
    }

    /// The panel's width: `preferred` (300 pt scaled with the text), kept to 80 percent of the window, or the whole window when
    /// that leaves a window narrower than 600 pt (a scrim strip too narrow to tap is worth less than the room for the words).
    static func panelWidth(preferred: CGFloat, available: CGFloat) -> CGFloat {
        let ceiling = available < 600 ? available : available * 0.8
        return min(preferred, ceiling)
    }

    private var isRightToLeft: Bool { effectiveUserInterfaceLayoutDirection == .rightToLeft }

    private func panelFrame(open: Bool) -> CGRect {
        let width = panelWidth
        let openX = isRightToLeft ? bounds.width - width : 0
        let closedX = isRightToLeft ? bounds.width : -width
        return CGRect(x: open ? openX : closedX, y: 0, width: width, height: bounds.height)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        shield.frame = bounds
        dim.frame = bounds
        let width = panelWidth
        // The strip beside the panel: the window less the panel, which has none left when the panel takes it all. It starts
        // below the status bar (the shield catches a tap up there).
        let strip = max(bounds.width - width, 0)
        let top = safeAreaInsets.top
        closeTarget.frame = CGRect(x: isRightToLeft ? 0 : width, y: top, width: strip, height: max(bounds.height - top, 0))
        if isOpen {
            panel.frame = panelFrame(open: true)
        } else if !isSettling {
            panel.frame = panelFrame(open: false)
        }
    }

    // MARK: - Open and close

    /// Slides the panel in, moves VoiceOver to its heading and starts blocking touches.
    public func open(animated: Bool) { setOpen(true, animated: animated) }

    /// Slides the panel away, announces the layout change and stops blocking touches once it has gone.
    public func close(animated: Bool) { setOpen(false, animated: animated) }

    private func setOpen(_ open: Bool, animated: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        let reduce = environment.reduceMotion
        settleToken += 1
        let token = settleToken
        if open {
            isSettling = false
            accessibilityElementsHidden = false
            shield.isHidden = false
            closeTarget.isHidden = false
            panel.isHidden = false
            layoutIfNeeded()
            let animations = {
                self.dim.alpha = 1
                self.panel.alpha = 1
                self.panel.frame = self.panelFrame(open: true)
            }
            guard animated else {
                animations()
                panel.moveAccessibilityFocusToHeading()
                return
            }
            if reduce {
                panel.frame = panelFrame(open: true)
                panel.alpha = 0
            } else {
                panel.frame = panelFrame(open: false)
                panel.alpha = 1
            }
            dim.alpha = 0
            // The standard spring; Reduce Motion fades in `quick`.
            if reduce {
                UIView.animate(withDuration: motion.quick, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: animations)
            } else {
                UIView.animate(springDuration: motion.standard.duration, bounce: CGFloat(motion.standard.bounce), options: [.allowUserInteraction], animations: animations)
            }
            panel.moveAccessibilityFocusToHeading()
        } else {
            let animations = {
                self.dim.alpha = 0
                if reduce { self.panel.alpha = 0 } else { self.panel.frame = self.panelFrame(open: false) }
            }
            let finish: (Bool) -> Void = { [weak self] _ in
                guard let self, self.settleToken == token else { return }
                self.isSettling = false
                self.accessibilityElementsHidden = true
                self.shield.isHidden = true
                self.closeTarget.isHidden = true
                self.panel.isHidden = true
                self.panel.alpha = 1
            }
            isSettling = animated
            if animated {
                if reduce {
                    UIView.animate(withDuration: motion.quick, delay: 0, options: [.curveEaseOut], animations: animations, completion: finish)
                } else {
                    UIView.animate(springDuration: motion.standard.duration, bounce: CGFloat(motion.standard.bounce), options: [], animations: animations, completion: finish)
                }
            } else {
                animations()
                finish(true)
            }
            FentonAnnouncer.layoutChanged(focus: returnFocusElement)
        }
    }

    // MARK: - Keyboard

    public override var keyCommands: [UIKeyCommand]? {
        guard isOpen else { return nil }
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapePressed))
        escape.wantsPriorityOverSystemBehavior = true
        return [escape]
    }

    @objc private func escapePressed() { onDismiss() }
    public override var canBecomeFirstResponder: Bool { isOpen }
}
#endif
