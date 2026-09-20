import Foundation

// Timers on the main thread that hold their owner only weakly. So far
// the same pattern showed up in about 20 places: `[weak self]`, then
// `MainActor.assumeIsolated { self?.… }`, sometimes with `invalidate()` once
// the owner is gone, sometimes without. Now once, and always with: a timer
// whose owner is gone stops itself instead of firing into the void.

@MainActor
public extension Timer {
    /// Calls `action` every `interval` seconds with the owner, as long
    /// as it still exists. Runs on the RunLoop of the main thread, like
    /// `scheduledTimer`.
    @discardableResult
    static func repeating<Owner: AnyObject & Sendable>(
        every interval: TimeInterval,
        tolerance: TimeInterval = 0,
        owner: Owner,
        _ action: @escaping @MainActor @Sendable (Owner) -> Void
    ) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak owner] timer in
            guard let owner else { return timer.invalidate() }
            MainActor.assumeIsolated { action(owner) }
        }
        timer.tolerance = tolerance
        return timer
    }

    /// Calls `action` once after `delay` seconds, if the owner
    /// still exists by then.
    @discardableResult
    static func once<Owner: AnyObject & Sendable>(
        after delay: TimeInterval,
        owner: Owner,
        _ action: @escaping @MainActor @Sendable (Owner) -> Void
    ) -> Timer {
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak owner] _ in
            guard let owner else { return }
            MainActor.assumeIsolated { action(owner) }
        }
    }
}
