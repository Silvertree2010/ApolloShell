import Foundation

@MainActor
public extension Timer {
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
