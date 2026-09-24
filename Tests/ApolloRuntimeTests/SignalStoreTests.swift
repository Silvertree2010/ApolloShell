import Testing
import Foundation
import AppKit
import ApolloConfig
@testable import ApolloRuntime

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
        store.subscribe(DependencyPath("perf", ["cpu"])) { notifications += 1 }

        for index in 0..<100 {
            store.set(DependencyPath("perf", ["cpu"]), .number(Double(index)))
        }
        scheduler.requestFlush { flushCount += 1 }
        scheduler.runPending()

        #expect(notifications == 100)
        #expect(flushCount == 1)
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

    @Test("RunLoop-Durchlauf liefert genau einen Flush, auch in eventTracking")
    func runLoopDeliversOneFlush() {
        let scheduler = RunLoopFlushScheduler()
        var flushes = 0

        scheduler.requestFlush { flushes += 1 }
        scheduler.requestFlush { flushes += 1 }
        scheduler.requestFlush { flushes += 1 }

        let keepAlive = Timer(timeInterval: 0.01, repeats: true) { _ in }
        RunLoop.main.add(keepAlive, forMode: .common)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        keepAlive.invalidate()
        #expect(flushes == 1)

        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
        flushes = 0
        scheduler.requestFlush { flushes += 1 }
        let eventTrackingKeepAlive = Timer(timeInterval: 0.01, repeats: true) { _ in }
        RunLoop.main.add(eventTrackingKeepAlive, forMode: .eventTracking)
        let eventTrackingDeadline = Date().addingTimeInterval(0.2)
        while Date() < eventTrackingDeadline {
            RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.01))
        }
        eventTrackingKeepAlive.invalidate()
        #expect(flushes == 1)
    }
}
