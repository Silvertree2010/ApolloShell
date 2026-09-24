import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Leistung-Logik")
struct PerformanceMathTests {
    // MARK: Netzwerk

    @Test("Rate aus zwei Zaehlerstaenden")
    func rate() {
        let old = NetCounters(received: 1_000, sent: 500)
        let new = NetCounters(received: 3_001_000, sent: 700_500)
        #expect(NetworkMath.rate(from: old, to: new, seconds: 2) == NetRate(download: 1_500_000, upload: 350_000))
    }

    @Test("Ueber 4 GB rechnen die 64-Bit-Zaehler einfach weiter")
    func rateBeyondFourGigabytes() {
        let old = NetCounters(received: 4_294_000_000, sent: 0)
        let new = NetCounters(received: 4_296_000_000, sent: 0)
        #expect(NetworkMath.rate(from: old, to: new, seconds: 1)?.download == 2_000_000)
    }

    @Test("Zurueckgesetzter Zaehler oder keine Zeit dazwischen: nil")
    func rateDegenerate() {
        let old = NetCounters(received: 10_000, sent: 10_000)
        #expect(NetworkMath.rate(from: old, to: NetCounters(received: 5, sent: 20_000), seconds: 1) == nil)
        #expect(NetworkMath.rate(from: old, to: NetCounters(received: 20_000, sent: 5), seconds: 1) == nil)
        #expect(NetworkMath.rate(from: old, to: NetCounters(received: 20_000, sent: 20_000), seconds: 0) == nil)
        #expect(NetworkMath.rate(from: old, to: NetCounters(received: 20_000, sent: 20_000), seconds: -1) == nil)
    }

    @Test("Nur echte Schnittstellen zaehlen: kein Loopback, kein VPN-Tunnel, keine Bruecke")
    func countedInterfaces() {
        #expect(NetworkMath.counts(flags: IFF_UP | IFF_BROADCAST, type: UInt8(IFT_ETHER)))            // en0
        #expect(!NetworkMath.counts(flags: IFF_UP | IFF_LOOPBACK, type: UInt8(IFT_LOOP)))            // lo0
        #expect(!NetworkMath.counts(flags: IFF_UP | IFF_POINTOPOINT, type: UInt8(IFT_OTHER)))        // utun
        #expect(!NetworkMath.counts(flags: IFF_UP | IFF_BROADCAST, type: UInt8(IFT_BRIDGE)))          // bridge0
    }

    @Test("Messer: erste Messung ohne Rate, danach Rate und Summe")
    func meterBasics() {
        var meter = NetworkMeter()
        meter.add(NetCounters(received: 1_000, sent: 100), at: 10)
        #expect(meter.rate == nil)
        #expect(meter.total == .zero)
        meter.add(NetCounters(received: 3_000, sent: 600), at: 11)
        #expect(meter.rate == NetRate(download: 2_000, upload: 500))
        #expect(meter.total == NetCounters(received: 2_000, sent: 500))
    }

    @Test("Messer: nach der Pause keine Rate, die Summe laeuft weiter")
    func meterPause() {
        var meter = NetworkMeter()
        meter.add(NetCounters(received: 0, sent: 0), at: 0)
        meter.add(NetCounters(received: 1_000, sent: 0), at: 1)
        meter.pause()
        #expect(meter.rate == nil)
        meter.add(NetCounters(received: 61_000, sent: 0), at: 61)
        #expect(meter.rate == nil) // ueber 60 s Pause gemittelt waere falsch
        #expect(meter.total.received == 61_000)
        meter.add(NetCounters(received: 62_000, sent: 0), at: 62)
        #expect(meter.rate?.download == 1_000)
    }

    @Test("Messer: Zaehler faellt (VPN weg) - kein Sprung, danach geht es weiter")
    func meterReset() {
        var meter = NetworkMeter()
        meter.add(NetCounters(received: 5_000, sent: 5_000), at: 0)
        meter.add(NetCounters(received: 1_000, sent: 1_000), at: 1)
        #expect(meter.rate == nil)
        #expect(meter.total == .zero)
        meter.add(NetCounters(received: 1_500, sent: 1_200), at: 2)
        #expect(meter.rate == NetRate(download: 500, upload: 200))
        #expect(meter.total == NetCounters(received: 500, sent: 200))
    }

    // MARK: Verlauf

    @Test("Verlauf behaelt nur die letzten 30 Werte, aeltester zuerst")
    func historyCapacity() {
        var history = SampleHistory(capacity: 30)
        for value in 1...35 { history.append(Double(value)) }
        #expect(history.values.count == 30)
        #expect(history.values.first == 6)
        #expect(history.values.last == 35)
        #expect(history.peak == 35)
        history.removeAll()
        #expect(history.values.isEmpty && history.peak == 0)
    }

    @Test("Verlaufslinie: rechtsbuendig, auf die Skala normiert, begrenzt")
    func sparklinePoints() {
        #expect(Sparkline.points([1, 2], capacity: 3, scale: 2) == [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)])
        #expect(Sparkline.points([4, -1], capacity: 2, scale: 2) == [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0)])
        #expect(Sparkline.points([3], capacity: 3, scale: 0) == [CGPoint(x: 1, y: 0)])
        #expect(Sparkline.points([], capacity: 30, scale: 1).isEmpty)
    }

    @Test("Skala: Maximum des Verlaufs, aber mindestens der Boden")
    func sparklineScale() {
        #expect(Sparkline.scale(peak: 2_000_000, floor: 10_000) == 2_000_000)
        #expect(Sparkline.scale(peak: 200, floor: 10_000) == 10_000)
    }

    // MARK: Texte

    @Test("Bytes auf Deutsch, dezimal", arguments: [
        (0.0, "0 B"),
        (999.0, "999 B"),
        (999.6, "1,0 KB"),       // gerundet 1000 B -> naechste Einheit
        (1_234.0, "1,2 KB"),
        (340_000.0, "340 KB"),
        (999_700.0, "1,0 MB"),
        (1_234_567.0, "1,2 MB"),
        (9_960_000.0, "10 MB"),  // 9,96 -> keine Nachkommastelle mehr
        (5_000_000_000.0, "5,0 GB"),
        (-5.0, "0 B"),
    ])
    func bytes(value: Double, text: String) {
        #expect(ByteFormat.bytes(value, locale: Locale(identifier: "de_DE")) == text)
    }

    @Test("Bytes auf Englisch: Punkt statt Komma")
    func bytesEnglish() {
        let en = Locale(identifier: "en_US")
        #expect(ByteFormat.bytes(1_234_567, locale: en) == "1.2 MB")
        #expect(ByteFormat.usage(used: 9_800_000_000, total: 16 << 30, binary: true, locale: en) == "9.1 GB of 16 GB")
    }

    @Test("Raten")
    func rates() {
        let de = Locale(identifier: "de_DE")
        #expect(ByteFormat.rate(1_200_000, locale: de) == "1,2 MB/s")
        #expect(ByteFormat.rate(1_200_000, locale: Locale(identifier: "en_US")) == "1.2 MB/s")
        #expect(ByteFormat.rate(340_000, locale: de) == "340 KB/s")
        #expect(ByteFormat.rate(512, locale: de) == "512 B/s")
    }

    @Test("Arbeitsspeicher binaer: 24 GB bleiben 24 GB")
    func binaryUsage() {
        let gib: UInt64 = 1 << 30
        #expect(ByteFormat.usage(used: 18 * gib, total: 24 * gib, binary: true) == "18 GB of 24 GB")
        #expect(ByteFormat.usage(used: 412_000_000_000, total: 994_000_000_000) == "412 GB of 994 GB")
    }

    @Test("Prozent mit Strich ohne Messwert")
    func percent() {
        #expect(PerformanceText.percent(nil) == "–")
        #expect(PerformanceText.percent(0.374) == "37 %")
        #expect(PerformanceText.percent(1.2) == "100 %")
        #expect(PerformanceText.percent(.nan) == "–")
    }

    @Test("Akku-Tank: Fuellstand und Texte")
    func batteryTank() {
        let onBattery = BatteryState(level: 80, charging: false, onAC: false)
        #expect(BatteryTankText.fill(onBattery) == 0.8)
        #expect(BatteryTankText.percent(onBattery) == "80 %")
        #expect(BatteryTankText.status(onBattery, minutes: 452) == "7h 32m Left")
        #expect(BatteryTankText.status(onBattery, minutes: -1) == "Calculating…")
        #expect(BatteryTankText.status(onBattery, minutes: nil) == "Calculating…")

        let charging = BatteryState(level: 35, charging: true, onAC: true)
        #expect(BatteryTankText.status(charging, minutes: 45) == "Full in 45m")
        #expect(BatteryTankText.status(charging, minutes: 0) == "Charging")

        #expect(BatteryTankText.status(BatteryState(level: 80, charging: false, onAC: true), minutes: 0) == "On Power Adapter")
        #expect(BatteryTankText.status(BatteryState(level: 100, charging: false, onAC: true), minutes: 0) == "Charged")
        #expect(BatteryTankText.fill(BatteryState(level: 120, charging: false, onAC: true)) == 1)
    }
}
