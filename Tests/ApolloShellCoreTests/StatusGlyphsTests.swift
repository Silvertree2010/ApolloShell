import Testing
@testable import ApolloShellCore

@Suite("Statussymbole der Leiste")
struct StatusGlyphsTests {
    @Test("Akku in Viertelschritten", arguments: [
        (5, "battery.0percent"), (20, "battery.25percent"), (50, "battery.50percent"),
        (77, "battery.75percent"), (95, "battery.100percent"),
    ])
    func batteryQuarters(level: Int, symbol: String) {
        #expect(StatusGlyphs.batterySymbol(BatteryState(level: level, charging: false, onAC: false)) == symbol)
    }

    @Test("beim Laden immer der Blitz")
    func chargingShowsBolt() {
        #expect(StatusGlyphs.batterySymbol(BatteryState(level: 30, charging: true, onAC: true)) == "battery.100percent.bolt")
    }

    @Test("ohne Akku kein Symbol")
    func noBatteryNoSymbol() {
        #expect(StatusGlyphs.batterySymbol(nil) == nil)
    }

    @Test("WLAN-Staerke nach dBm", arguments: [
        (-43, 1.0), (-60, 0.66), (-70, 0.33), (-85, 0.1),
    ])
    func wifiStrength(rssi: Int, strength: Double) {
        let result = StatusGlyphs.wifi(powerOn: true, rssi: rssi)
        #expect(result.symbol == "wifi")
        #expect(result.strength == strength)
    }

    @Test("WLAN aus zeigt das durchgestrichene Symbol")
    func wifiOff() {
        #expect(StatusGlyphs.wifi(powerOn: false, rssi: -40).symbol == "wifi.slash")
    }

    @Test("WLAN an, aber nicht verbunden: leere Balken")
    func wifiNotConnected() {
        #expect(StatusGlyphs.wifi(powerOn: true, rssi: 0).strength == 0)
    }

    @Test("Akkutext")
    func batteryText() {
        #expect(StatusGlyphs.batteryText(BatteryState(level: 77, charging: true, onAC: true)) == "Battery 77%, charging")
        #expect(StatusGlyphs.batteryText(BatteryState(level: 50, charging: false, onAC: false)) == "Battery 50%")
    }
}
