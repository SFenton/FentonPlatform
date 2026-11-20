#if os(iOS)
import UIKit

/// Swaps a panel's content without a hard cut: the old content fades out, the new one is swapped in while hidden (optionally
/// animating the layout change, so a shorter panel collapses), then fades in. A key requested mid-transition is picked up at the
/// next swap, so rapid taps settle on the last one. With Reduce Motion the swap is immediate. Timings: ``Timing``.
///
/// ```swift
/// let swap = FentonContentSwapView<Tab>(initial: .controls, reduceMotion: { env.reduceMotion }) { tab in makeView(for: tab) }
/// swap.show(.apps)                       // fades out, swaps, fades in
/// ```
@MainActor
public final class FentonContentSwapView<Key: Equatable>: UIView {
    // MARK: - Timing

    /// Durations, in seconds.
    public struct Timing: Equatable {
        /// The old content fading out.
        public var fadeOut = 0.13
        /// The new content fading in.
        public var fadeIn = 0.17
        /// The swap's layout animation, when ``FentonContentSwapView/animatesLayout`` asks for one.
        public var layout = 0.28

        /// Creates the default timing.
        public init() {}
    }

    // MARK: - Properties

    /// The key whose content is on screen.
    public private(set) var displayed: Key
    /// The last key asked for.
    public private(set) var target: Key
    /// Durations of the swap.
    public var timing = Timing()
    /// Whether the swap from one key to the next animates the layout (e.g. tabs collapsing). Default: never.
    public var animatesLayout: (Key, Key) -> Bool = { _, _ in false }
    /// Called right after each swap, while the content is hidden (e.g. to reset the scroll position).
    public var didSwap: (Key) -> Void = { _ in }
    /// Whether a transition is in flight: a publication must not replace the panel while it runs.
    public var isTransitioning: Bool { running }

    private let makeContent: (Key) -> UIView
    private let reduceMotion: () -> Bool
    private let container = UIView()
    private var running = false
    private var generation = 0

    // MARK: - Creating

    /// Creates the view showing `initial`'s content.
    /// - Parameters:
    ///   - initial: The key shown first.
    ///   - reduceMotion: Read at each ``show(_:)``: true swaps immediately.
    ///   - makeContent: Builds the content for a key.
    public init(initial: Key, reduceMotion: @escaping () -> Bool, makeContent: @escaping (Key) -> UIView) {
        displayed = initial
        target = initial
        self.reduceMotion = reduceMotion
        self.makeContent = makeContent
        super.init(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor), container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor), container.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        install(initial)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func install(_ key: Key) {
        container.subviews.forEach { $0.removeFromSuperview() }
        let content = makeContent(key)
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor), content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor), content.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }

    // MARK: - Showing

    /// Asks for `key`'s content.
    public func show(_ key: Key) {
        target = key
        if reduceMotion() {
            generation += 1
            running = false
            container.alpha = 1
            guard displayed != key else { return }
            displayed = key
            install(key)
            didSwap(key)
            return
        }
        guard !running, displayed != key else { return }
        running = true
        generation += 1
        let generation = generation
        UIView.animate(withDuration: timing.fadeOut, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.container.alpha = 0
        } completion: { [weak self] _ in self?.swap(generation) }
    }

    private func swap(_ generation: Int) {
        guard running, generation == self.generation else { return }
        let next = target
        let previous = displayed
        if next != previous, animatesLayout(previous, next) {
            displayed = next
            install(next)
            UIView.animate(withDuration: timing.layout, delay: 0, options: .curveEaseInOut) {
                self.superview?.layoutIfNeeded()
                self.layoutIfNeeded()
            } completion: { [weak self] _ in
                guard let self, generation == self.generation else { return }
                self.didSwap(next)
                self.fadeIn(generation)
            }
        } else {
            if next != previous {
                displayed = next
                install(next)
                didSwap(next)
            }
            fadeIn(generation)
        }
    }

    private func fadeIn(_ generation: Int) {
        guard running, generation == self.generation else { return }
        // A newer key arrived during the swap: swap again while still hidden.
        if target != displayed { swap(generation); return }
        UIView.animate(withDuration: timing.fadeIn, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.container.alpha = 1
        } completion: { [weak self] _ in
            guard let self, generation == self.generation else { return }
            self.running = false
            if self.target != self.displayed { self.show(self.target) }
        }
    }
}
#endif
