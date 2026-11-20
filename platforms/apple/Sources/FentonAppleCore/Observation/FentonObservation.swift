import Foundation
import Observation

/// Binds imperative UI to `@Observable` models the way SwiftUI's view graph does: `apply` runs once now, records every
/// observable property it reads, and runs again on the main actor after any of them changes. Several changes in one run-loop
/// turn cost one re-run, so a live update to one entity costs the views that read it one update and nothing else.
///
/// Keep the returned token for as long as the binding should live (``FentonObservationBag`` does this for a view or controller);
/// dropping it stops the updates.
@MainActor
public final class FentonObservation {
    // MARK: - State

    private let track: @MainActor () -> Void
    private let apply: (@MainActor () -> Void)?
    private var isScheduled = false
    private var isCancelled = false
    private var isPaused = false
    /// An input changed while the observation was paused, so it owes one run when it resumes.
    private var isStale = false

    // MARK: - Lifecycle

    /// Starts observing.
    /// - Parameter apply: Reads observable state and writes it into views. Runs now and after every change it read.
    public init(_ apply: @escaping @MainActor () -> Void) {
        track = apply
        self.apply = nil
        run()
    }

    /// Starts observing only what `track` reads; `apply` runs after it, outside the tracking scope.
    ///
    /// Use it when `apply` builds or rebuilds UIKit views. Reads UIKit makes while views are built and laid out are observable
    /// to Observation too, and UIKit mutates them on every layout pass: inside the tracking scope they re-run the rebuild on
    /// every frame.
    /// - Parameters:
    ///   - track: Reads the observable state that should re-run `apply`, and nothing else.
    ///   - apply: Writes into views. Runs now and after every change `track` read.
    public init(track: @escaping @MainActor () -> Void, apply: @escaping @MainActor () -> Void) {
        self.track = track
        self.apply = apply
        run()
    }

    /// Stops the updates. An already-running closure is not interrupted.
    public func cancel() { isCancelled = true }

    // MARK: - Resting

    /// Holds the re-runs: an input that changes meanwhile is remembered, costs nothing more, and the observation runs once when
    /// ``resume()`` is called. Its tracking is not touched, so a change in the next instant is still heard.
    public func pause() { isPaused = true }

    /// Lets the observation run again, now and in this call when an input changed while it was paused: one catch-up run, in the
    /// caller's turn, so what it draws is current before the next frame.
    /// - Returns: Whether it ran.
    @discardableResult
    public func resume() -> Bool {
        guard isPaused else { return false }
        isPaused = false
        guard isStale, !isCancelled else { return false }
        isStale = false
        run()
        return true
    }

    // MARK: - Running

    private func run() {
        guard !isCancelled else { return }
        withObservationTracking { track() } onChange: { [weak self] in
            // `onChange` fires in the mutation's `willSet`, on whatever thread mutated: hop to the main actor and read the
            // new value on the next turn, once for any number of changes.
            Task { @MainActor [weak self] in self?.schedule() }
        }
        apply?()
    }

    private func schedule() {
        guard !isScheduled, !isCancelled else { return }
        // Paused: the change is remembered and the one catch-up run happens at ``resume()``; nothing is queued for it.
        if isPaused { isStale = true; return }
        isScheduled = true
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isScheduled = false
                if self.isPaused { self.isStale = true; return }
                self.run()
            }
        }
    }
}
