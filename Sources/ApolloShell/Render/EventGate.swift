import Foundation
import ApolloConfig

@MainActor
protocol GateClock: AnyObject {
    var now: Double { get }
    func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void)
}

@MainActor
final class SystemGateClock: GateClock {
    var now: Double { ProcessInfo.processInfo.systemUptime }

    func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { work() }
        }
    }
}

@MainActor
final class EventGate {
    private let clock: any GateClock
    private var lastFire = -Double.infinity
    private var generation = 0
    private var scrolled = 0.0

    init(clock: any GateClock) {
        self.clock = clock
    }

    enum Outcome {
        case fired, deferred, dropped
    }

    @discardableResult
    func submit(_ event: Record, rules: HandlerRules, fire: @escaping @MainActor (Record) -> Void) -> Outcome {
        var event = event
        if let step = rules.step, step > 0 {
            if event["phase"] == .string("began") { scrolled = 0 }
            let dy = StyleValues.numberValue(event["dy"] ?? .null) ?? 0
            let precise = event["precise"] != .bool(false)
            scrolled += abs(dy) * (precise ? 1 : 10)
            guard scrolled >= step else { return .dropped }
            if let cooldown = rules.cooldown, clock.now - lastFire <= cooldown { return .dropped }
            scrolled = 0
            event["direction"] = .string(dy >= 0 ? "up" : "down")
        } else if let cooldown = rules.cooldown, clock.now - lastFire <= cooldown {
            return .dropped
        }
        if let throttle = rules.throttle, clock.now - lastFire < throttle { return .dropped }
        if let debounce = rules.debounce, debounce > 0 {
            generation += 1
            let ticket = generation
            clock.after(debounce) { [weak self] in
                guard let self, self.generation == ticket else { return }
                self.lastFire = self.clock.now
                fire(event)
            }
            return .deferred
        }
        lastFire = clock.now
        fire(event)
        return .fired
    }
}
