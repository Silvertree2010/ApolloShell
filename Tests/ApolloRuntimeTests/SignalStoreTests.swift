import Testing
import Foundation
import ApolloConfig
@testable import ApolloRuntime

private let eventTrackingMode = RunLoop.Mode("NSEventTrackingRunLoopMode")

@MainActor
@Suite("SignalStore und FlushScheduler")
struct SignalStoreTests {
    @Test("Präfix-Regel: Vorfahr, Nachfahr, Geschwister, fremde Wurzel")
    func prefixRule() {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)

        var ancestorHits = 0
        var descendantHits = 0
        var siblingHits = 0
        var foreignHits = 0

        store.subscribe(DependencyPath("apps", [])) { ancestorHits += 1 }
        store.subscribe(DependencyPath("apps", ["running", "count"])) { descendantHits += 1 }
        store.subscribe(DependencyPath("apps", ["dock"])) { siblingHits += 1 }
        store.subscribe(DependencyPath("perf", ["cpu"])) { foreignHits += 1 }

        store.set(DependencyPath("apps", ["running"]), .number(3))
        scheduler.runPending()

        #expect(ancestorHits == 1)
        #expect(descendantHits == 1)
        #expect(siblingHits == 0)
        #expect(foreignHits == 0)
    }

    @Test("100 Schreibvorgänge vor runPending ergeben einen Flush")
    func batchedFlush() {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        var flushCount = 0
        var notifications = 0
        store.onFlush = { flushCount += 1 }
        store.subscribe(DependencyPath("perf", ["cpu"])) { notifications += 1 }

        for index in 0..<100 {
            store.set(DependencyPath("perf", ["cpu"]), .number(Double(index)))
        }
        #expect(flushCount == 0)
        scheduler.runPending()

        #expect(notifications == 100)
        #expect(flushCount == 1)

        store.set(DependencyPath("perf", ["cpu"]), .number(-1))
        scheduler.runPending()
        #expect(flushCount == 2)
    }

    @Test("Schreiben aus dem Flush heraus stösst einen neuen Durchlauf an")
    func writeDuringFlushSchedulesNextPass() {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        var flushCount = 0
        store.onFlush = {
            flushCount += 1
            if flushCount == 1 {
                store.set(DependencyPath("perf", ["cpu"]), .number(2))
            }
        }
        store.set(DependencyPath("perf", ["cpu"]), .number(1))
        scheduler.runPending()
        #expect(flushCount == 1)
        scheduler.runPending()
        #expect(flushCount == 2)
    }

    @Test("Der Scheduler sammelt Anfragen statt sie zu überschreiben")
    func schedulerCollectsRequests() {
        let scheduler = ManualFlushScheduler()
        var first = 0
        var second = 0
        scheduler.requestFlush { first += 1 }
        scheduler.requestFlush { second += 1 }
        scheduler.runPending()
        #expect(first == 1)
        #expect(second == 1)
    }

    @Test("Gleicher Wert löst keine Meldung aus")
    func sameValueNoNotification() {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        var hits = 0
        store.set(DependencyPath("perf", ["cpu"]), .number(1))
        store.subscribe(DependencyPath("perf", ["cpu"])) { hits += 1 }
        store.set(DependencyPath("perf", ["cpu"]), .number(1))
        #expect(hits == 0)
    }

    @Test("NaN und Unendlich werden beim Eintritt null")
    func nanAndInfinityBecomeNull() {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        store.set(DependencyPath("perf", ["cpu"]), .number(Double.nan))
        #expect(store.value(DependencyPath("perf", ["cpu"])) == .null)
        store.set(DependencyPath("perf", ["cpu"]), .number(2))
        store.set(DependencyPath("perf", ["cpu"]), .number(.infinity))
        #expect(store.value(DependencyPath("perf", ["cpu"])) == .null)
        store.set(DependencyPath("perf", ["load"]), .record(Record([("value", .number(-Double.infinity))])))
        #expect(store.value(DependencyPath("perf", ["load", "value"])) == .null)
    }

    @Test("Saubere Werte bleiben beim Eintritt dieselben Speicherobjekte, NaN in der Tiefe wird null")
    func sanitizeKeepsSharing() {
        let record = Value.record(Record([("id", .string("a")), ("n", .number(1))]))
        let clean = Value.list([record, .list([record]), .string("x")])
        #expect(ShellRuntime.identical(SignalStore.sanitize(clean), clean))
        #expect(ShellRuntime.identical(SignalStore.sanitize(record), record))
        let dirty = Value.list([record, .record(Record([("n", .number(.nan))]))])
        let sanitized = SignalStore.sanitize(dirty)
        #expect(sanitized == .list([record, .record(Record([("n", .null)]))]))
        #expect(!ShellRuntime.identical(sanitized, dirty))
    }

    static func depth(of value: Value) -> Int {
        var current = value
        var depth = 0
        while case .list(let items) = current, let first = items.first {
            depth += 1
            current = first
        }
        return depth
    }

    @Test("Werte tiefer als 256 Ebenen werden beim Eintritt abgeschnitten, auch wenn sie immer wieder eingepackt werden")
    func deepValuesAreCut() {
        let store = SignalStore(scheduler: ManualFlushScheduler())
        let path = DependencyPath("data", ["x"])
        store.set(path, .number(1))
        for _ in 0..<1_000 {
            store.set(path, .list([store.value(path)]))
        }
        let stored = store.value(path)
        #expect(Self.depth(of: stored) == RuntimeLimits.valueDepth)
        var innermost = stored
        while case .list(let items) = innermost, let first = items.first { innermost = first }
        #expect(innermost == .null)
        var shallow = Value.number(1)
        for _ in 0..<RuntimeLimits.valueDepth { shallow = .list([shallow]) }
        #expect(ShellRuntime.identical(SignalStore.sanitize(shallow), shallow))
    }

    @Test("Verschachteltes requestFlush während eines Flushs stösst einen neuen Durchlauf an")
    func nestedRequestFlushSchedulesNewPass() {
        let scheduler = ManualFlushScheduler()
        var outerRuns = 0
        var innerRuns = 0
        scheduler.requestFlush {
            outerRuns += 1
            scheduler.requestFlush { innerRuns += 1 }
        }
        scheduler.runPending()
        #expect(outerRuns == 1)
        #expect(innerRuns == 0)
        scheduler.runPending()
        #expect(innerRuns == 1)
    }

    #if canImport(Darwin)
    @Test("RunLoop-Durchlauf liefert genau einen Flush, auch in eventTracking")
    func runLoopDeliversOneFlush() {
        let scheduler = RunLoopFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        var flushes = 0
        var otherRequests = 0
        store.onFlush = { flushes += 1 }

        store.set(DependencyPath("perf", ["cpu"]), .number(1))
        store.set(DependencyPath("perf", ["cpu"]), .number(2))
        store.set(DependencyPath("perf", ["load"]), .number(3))
        scheduler.requestFlush { otherRequests += 1 }

        let keepAlive = Timer(timeInterval: 0.01, repeats: true) { _ in }
        RunLoop.main.add(keepAlive, forMode: .common)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        keepAlive.invalidate()
        #expect(flushes == 1)
        #expect(otherRequests == 1)

        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(eventTrackingMode.rawValue as CFString))
        flushes = 0
        store.set(DependencyPath("perf", ["cpu"]), .number(4))
        store.set(DependencyPath("perf", ["cpu"]), .number(5))
        let eventTrackingKeepAlive = Timer(timeInterval: 0.01, repeats: true) { _ in }
        RunLoop.main.add(eventTrackingKeepAlive, forMode: eventTrackingMode)
        let eventTrackingDeadline = Date().addingTimeInterval(0.2)
        while Date() < eventTrackingDeadline {
            RunLoop.main.run(mode: eventTrackingMode, before: Date().addingTimeInterval(0.01))
        }
        eventTrackingKeepAlive.invalidate()
        #expect(flushes == 1)
    }
    #endif
}
