import Testing
@testable import ApolloShellCore

@Suite("Längste Main-Actor-Blockade je Runloop-Durchlauf (V7, testing.md 4)")
struct BlockMeterTests {
    let ms: UInt64 = 1_000_000

    @Test("liefert den längsten Durchlauf in ms und beginnt danach neu")
    func longestThenReset() {
        var meter = BlockMeter()
        meter.began(at: 0)
        meter.ended(at: 5 * ms)
        meter.began(at: 10 * ms)
        meter.ended(at: 12 * ms)
        #expect(meter.take(now: 20 * ms) == 5)
        #expect(meter.take(now: 21 * ms) == 0)
    }

    @Test("ein laufender Durchlauf zählt bis zum Aufruf und danach ab dem Aufruf")
    func runningIteration() {
        var meter = BlockMeter()
        meter.began(at: 30 * ms)
        #expect(meter.take(now: 38 * ms) == 8)
        meter.ended(at: 40 * ms)
        #expect(meter.take(now: 50 * ms) == 2)
    }

    @Test("Ende ohne Beginn zählt nicht")
    func endWithoutBegin() {
        var meter = BlockMeter()
        meter.ended(at: 9 * ms)
        #expect(meter.take(now: 10 * ms) == 0)
    }
}
