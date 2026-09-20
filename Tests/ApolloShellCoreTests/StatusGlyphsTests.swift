import Testing
@testable import ApolloShellCore

@Suite("Status symbols of the bar")
struct StatusGlyphsTests {
    @Test("Battery in quarter steps", arguments: [
        (5, "battery.0percent"), (20, "battery.25percent"), (50, "battery.50percent"),
        (77, "battery.75percent"), (95, "battery.100percent"),
    ])
    func batteryQuarters(level: Int, symbol: String) {
        #expect(StatusGlyphs.batterySymbol(BatteryState(level: level, charging: false, onAC: false)) == symbol)
    }

    @Test("Bolt always shown while charging")
    func chargingShowsBolt() {
        #expect(StatusGlyphs.batterySymbol(BatteryState(level: 30, charging: true, onAC: true)) == "battery.100percent.bolt")
    }

    @Test("No symbol without a battery")
    func noBatteryNoSymbol() {
        #expect(StatusGlyphs.batterySymbol(nil) == nil)
    }

    @Test("WLAN strength by dBm", arguments: [
        (-43, 1.0), (-60, 0.66), (-70, 0.33), (-85, 0.1),
    ])
    func wifiStrength(rssi: Int, strength: Double) {
        let result = StatusGlyphs.wifi(powerOn: true, rssi: rssi)
        #expect(result.symbol == "wifi")
        #expect(result.strength == strength)
    }

    @Test("WLAN off shows the slashed symbol")
    func wifiOff() {
        #expect(StatusGlyphs.wifi(powerOn: false, rssi: -40).symbol == "wifi.slash")
    }

    @Test("WLAN on but not connected: empty bars")
    func wifiNotConnected() {
        #expect(StatusGlyphs.wifi(powerOn: true, rssi: 0).strength == 0)
    }

    @Test("Battery text")
    func batteryText() {
        #expect(StatusGlyphs.batteryText(BatteryState(level: 77, charging: true, onAC: true)) == "Battery 77%, charging")
        #expect(StatusGlyphs.batteryText(BatteryState(level: 50, charging: false, onAC: false)) == "Battery 50%")
    }
}
