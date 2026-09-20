import Testing
@testable import ApolloShellCore

@Suite("Detailfenster: WLAN-Signal")
struct StatusPopoutSignalTests {
    @Test("Balken und Urteil nach dBm, gleiche Schwellen wie das Leistensymbol", arguments: [
        (-40, 3, "Excellent"), (-55, 3, "Excellent"), (-56, 2, "Good"), (-67, 2, "Good"),
        (-70, 1, "Fair"), (-75, 1, "Fair"), (-76, 0, "Weak"), (-90, 0, "Weak"),
    ])
    func barsAndQuality(rssi: Int, bars: Int, quality: String) {
        #expect(StatusPopoutSignal.bars(rssi: rssi) == bars)
        #expect(StatusPopoutSignal.quality(rssi: rssi) == quality)
    }

    @Test("nicht verbunden (0 oder nil): keine Balken, kein Signal", arguments: [Int?.none, 0])
    func noSignal(rssi: Int?) {
        #expect(StatusPopoutSignal.bars(rssi: rssi) == 0)
        #expect(StatusPopoutSignal.quality(rssi: rssi) == "No Signal")
    }

    @Test("Signal-Rauschabstand, fehlende Werte ergeben nil", arguments: [
        (Int?.some(-50), Int?.some(-95), Int?.some(45)),
        (Int?.some(-50), Int?.some(0), Int?.none),
        (Int?.none, Int?.some(-95), Int?.none),
    ])
    func snr(rssi: Int?, noise: Int?, expected: Int?) {
        #expect(StatusPopoutSignal.signalToNoise(rssi: rssi, noise: noise) == expected)
    }

    @Test("PHY-Modus aus CoreWLANs Rohwert", arguments: [
        (6, String?.some("Wi-Fi 6 (802.11ax)")), (5, String?.some("Wi-Fi 5 (802.11ac)")),
        (0, String?.none), (99, String?.none),
    ])
    func phyMode(raw: Int, name: String?) {
        #expect(StatusPopoutSignal.phyModeName(rawValue: raw) == name)
    }

    @Test("Band aus CoreWLANs Rohwert", arguments: [
        (1, String?.some("2,4 GHz")), (2, String?.some("5 GHz")), (3, String?.some("6 GHz")), (0, String?.none),
    ])
    func band(raw: Int, name: String?) {
        #expect(StatusPopoutSignal.bandName(rawValue: raw) == name)
    }
}

@Suite("Detailfenster: Akku")
struct StatusPopoutBatteryTests {
    @Test("Dauer in hours und Minuten", arguments: [
        (135, String?.some("2h 15m")), (60, String?.some("1h")), (45, String?.some("45m")),
        (1, String?.some("1m")), (600, String?.some("10h")), (0, String?.none), (-1, String?.none),
    ])
    func duration(minutes: Int, text: String?) {
        #expect(StatusPopoutDuration.text(minutes: minutes) == text)
    }

    @Test("Zustand in Worten", arguments: [
        (true, true, "Charging"), (false, true, "On Power"), (false, false, "Battery"),
    ])
    func state(charging: Bool, onAC: Bool, text: String) {
        #expect(StatusPopoutBatteryText.state(BatteryState(level: 50, charging: charging, onAC: onAC)) == text)
    }

    @Test("Zeitzeile je nach Zustand", arguments: [
        (40, true, true, 0, 83, "Full in 1h 23m"),
        (40, true, true, 0, -1, "Calculating charge time…"),
        (100, false, true, 0, 0, "Fully Charged"),
        (80, false, true, 0, 0, "Not Charging Right Now"),
        (70, false, false, 135, 0, "2h 15m Left"),
        (70, false, false, -1, 0, "Calculating time remaining…"),
    ])
    func timeLine(level: Int, charging: Bool, onAC: Bool, toEmpty: Int, toFull: Int, text: String) {
        let battery = BatteryState(level: level, charging: charging, onAC: onAC)
        #expect(StatusPopoutBatteryText.time(battery, minutesToEmpty: toEmpty, minutesToFull: toFull) == text)
    }

    @Test("Maximale Kapazitaet: roh vor nominal, bei 100 gedeckelt", arguments: [
        (Int?.some(8694), Int?.some(8938), Int?.some(8579), Int?.some(100)),
        (Int?.some(7000), Int?.some(7200), Int?.some(8000), Int?.some(88)),
        (Int?.none, Int?.some(6000), Int?.some(8000), Int?.some(75)),
        (Int?.some(0), Int?.some(6000), Int?.some(8000), Int?.some(75)),
        (Int?.some(7000), Int?.none, Int?.some(0), Int?.none),
        (Int?.none, Int?.none, Int?.some(8000), Int?.none),
    ])
    func health(rawMax: Int?, nominal: Int?, design: Int?, expected: Int?) {
        #expect(StatusPopoutBatteryHealth.percent(rawMax: rawMax, nominal: nominal, design: design) == expected)
    }
}

@Suite("Detailfenster: Lage neben dem Symbol")
struct StatusPopoutPlacementTests {
    @Test("mittig auf dem Symbol, aber immer ganz im Bereich", arguments: [
        (500.0, 200.0, 1000.0, 400.0),
        (50.0, 200.0, 1000.0, 0.0),
        (980.0, 200.0, 1000.0, 800.0),
        (500.0, 1200.0, 1000.0, 0.0),
    ])
    func top(anchor: Double, height: Double, container: Double, expected: Double) {
        #expect(StatusPopoutPlacement.top(anchorY: anchor, height: height, containerHeight: container) == expected)
    }
}
