/// Holds a view's or controller's observations; they end with it.
@MainActor
public final class FentonObservationBag {
    private var observations: [FentonObservation] = []

    /// Whether the bag's observations rest (``pause()``): the first run of a new observation still happens, so its views are
    /// drawn from it.
    public private(set) var isPaused = false

    /// Creates a bag with no observations.
    public init() {}

    // MARK: - Observing

    /// Observes `apply` (``FentonObservation``) for the bag's lifetime.
    public func observe(_ apply: @escaping @MainActor () -> Void) {
        add(FentonObservation(apply))
    }

    /// Observes what `track` reads and runs `apply` after it, outside the tracking scope (``FentonObservation/init(track:apply:)``).
    public func observe(track: @escaping @MainActor () -> Void, apply: @escaping @MainActor () -> Void) {
        add(FentonObservation(track: track, apply: apply))
    }

    /// Observes with a weak owner capture to avoid owner, bag and closure cycles.
    ///
    /// Use this overload when the closure needs an owning controller or view. The closure does not run again once the owner is
    /// released.
    public func observe<Owner: AnyObject>(
        owner: Owner,
        apply: @escaping @MainActor (Owner) -> Void
    ) {
        observe { [weak owner] in
            guard let owner else { return }
            apply(owner)
        }
    }

    private func add(_ observation: FentonObservation) {
        if isPaused { observation.pause() }
        observations.append(observation)
    }

    // MARK: - Resting

    /// Rests every observation of the bag, and any made later, until ``resume()``: a view that is not on screen is not re-drawn
    /// for each change.
    public func pause() {
        isPaused = true
        observations.forEach { $0.pause() }
    }

    /// Ends the rest. Each observation whose inputs changed meanwhile runs once, now and in this call, so the views are current
    /// when it returns.
    /// - Returns: How many observations caught up.
    @discardableResult
    public func resume() -> Int {
        isPaused = false
        return observations.reduce(0) { $0 + ($1.resume() ? 1 : 0) }
    }

    // MARK: - Ending

    /// Cancels and removes every observation, for a reused cell before it binds to another model.
    public func removeAll() {
        observations.forEach { $0.cancel() }
        observations.removeAll()
    }
}
