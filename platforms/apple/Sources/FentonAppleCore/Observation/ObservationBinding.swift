import Foundation
import Observation

/// A main-actor binding between an Observation model and imperative UI.
///
/// The closure runs immediately, records the observable properties it reads, and
/// runs once on the next run-loop turn after any of those properties changes.
@MainActor
public final class ObservationBinding {
    private let apply: @MainActor () -> Void
    private var scheduled = false
    private var cancelled = false

    public init(apply: @escaping @MainActor () -> Void) {
        self.apply = apply
        run()
    }

    /// Stops future invalidation updates. An already-running closure is not interrupted.
    public func cancel() {
        cancelled = true
    }

    private func run() {
        guard !cancelled else { return }
        withObservationTracking { apply() } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.schedule() }
        }
    }

    private func schedule() {
        guard !scheduled, !cancelled else { return }
        scheduled = true
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scheduled = false
                self.run()
            }
        }
    }
}

/// Owns bindings for a view or controller and cancels them together.
@MainActor
public final class ObservationBag {
    private var bindings: [ObservationBinding] = []

    /// Creates a bag with no bindings.
    public init() {}

    /// Adds a binding that is cancelled when the bag is cleared or released.
    public func observe(_ apply: @escaping @MainActor () -> Void) {
        bindings.append(ObservationBinding(apply: apply))
    }

    /// Adds a binding with a weak owner capture to avoid owner–bag–closure cycles.
    ///
    /// Use this overload when the closure needs an owning controller or view
    /// object. Existing call sites should continue to use an explicit
    /// `[weak self]` capture when that is clearer for their consumer.
    public func observe<Owner: AnyObject>(
        owner: Owner,
        apply: @escaping @MainActor (Owner) -> Void
    ) {
        observe { [weak owner] in
            guard let owner else { return }
            apply(owner)
        }
    }

    /// Cancels and removes every binding.
    public func removeAll() {
        bindings.forEach { $0.cancel() }
        bindings.removeAll()
    }
}
