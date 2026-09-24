import Foundation

// Timer auf dem Hauptthread, die ihren Besitzer nur schwach halten. Bisher
// stand an rund 20 Stellen dieselbe Form: `[weak self]`, dann
// `MainActor.assumeIsolated { self?.… }`, teils mit `invalidate()`, sobald
// der Besitzer weg ist, teils ohne. Jetzt einmal, und immer mit: ein Timer,
// dessen Besitzer weg ist, beendet sich selbst statt ins Leere zu feuern.

@MainActor
public extension Timer {
    /// Ruft `action` alle `interval` Sekunden mit dem Besitzer auf, solange
    /// es ihn gibt. Laeuft auf der RunLoop des Hauptthreads, wie
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

    /// Ruft `action` einmal nach `delay` Sekunden auf, falls es den Besitzer
    /// dann noch gibt.
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
