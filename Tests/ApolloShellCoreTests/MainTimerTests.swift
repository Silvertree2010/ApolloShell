import Foundation
import Testing
@testable import ApolloShellCore

@MainActor
private final class Counter {
    var count = 0
}

@Suite("Timer on the main thread")
@MainActor
struct MainTimerTests {
    /// Runs the main thread's RunLoop until `done` is true or the
    /// time is up.
    private func spin(for seconds: TimeInterval, until done: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    @Test("Repeats as long as the owner lives")
    func repeats() {
        let counter = Counter()
        let timer = Timer.repeating(every: 0.01, tolerance: 0.005, owner: counter) { $0.count += 1 }
        defer { timer.invalidate() }
        #expect(timer.tolerance == 0.005)
        spin(for: 2) { counter.count >= 3 }
        #expect(counter.count >= 3)
    }

    @Test("A repeating timer stops itself without an owner")
    func stopsWithoutOwner() {
        var counter: Counter? = Counter()
        let timer = Timer.repeating(every: 0.01, owner: counter!) { $0.count += 1 }
        counter = nil
        spin(for: 2) { !timer.isValid }
        #expect(!timer.isValid)
    }

    @Test("Once: fires once, not at all without an owner")
    func once() {
        let counter = Counter()
        Timer.once(after: 0.01, owner: counter) { $0.count += 1 }
        var gone: Counter? = Counter()
        let ignored = Timer.once(after: 0.01, owner: gone!) { _ in Issue.record("owner is gone") }
        gone = nil
        spin(for: 2) { counter.count == 1 && !ignored.isValid }
        spin(for: 0.05)
        #expect(counter.count == 1)
        #expect(!ignored.isValid)
    }
}
