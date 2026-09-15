import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Utilities-Panel: Wach halten")
struct KeepAwakeTextTests {
    /// Feste Zeitzone, damit der Test nicht von der Maschine abhaengt.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    @Test("aus: normaler Energiesparmodus")
    func inactive() {
        #expect(KeepAwakeText.subtitle(since: nil, now: date(14, 12, 0), calendar: calendar) == "Mac schläft normal")
    }

    @Test("heute: nur die Uhrzeit, zweistellig")
    func today() {
        #expect(KeepAwakeText.subtitle(since: date(14, 14, 30), now: date(14, 15, 0), calendar: calendar) == "Aktiv seit 14:30")
        #expect(KeepAwakeText.subtitle(since: date(14, 0, 5), now: date(14, 9, 0), calendar: calendar) == "Aktiv seit 00:05")
    }

    @Test("ueber Mitternacht: gestern")
    func yesterday() {
        #expect(KeepAwakeText.subtitle(since: date(13, 23, 10), now: date(14, 7, 0), calendar: calendar) == "Aktiv seit gestern, 23:10")
    }

    @Test("aelter: mit Datum")
    func older() {
        #expect(KeepAwakeText.subtitle(since: date(9, 8, 4), now: date(14, 7, 0), calendar: calendar) == "Aktiv seit 09.09., 08:04")
    }
}

@Suite("Utilities-Panel: Schnellschalter")
struct QuickTogglesTests {
    @Test("WLAN: an leuchtet, aus nicht, ohne Interface nicht klickbar")
    func wifi() {
        #expect(QuickToggles.wifi(powerOn: true) == QuickToggleLook(symbol: "wifi", active: true, enabled: true, help: "WLAN an"))
        #expect(QuickToggles.wifi(powerOn: false).active == false)
        #expect(QuickToggles.wifi(powerOn: false).symbol == "wifi.slash")
        #expect(QuickToggles.wifi(powerOn: nil).enabled == false)
    }

    @Test("Mikrofon leuchtet, solange es NICHT stumm ist (wie Caelestia)")
    func microphone() {
        let live = QuickToggles.microphone(muted: false, settable: true)
        #expect(live.active && live.enabled && live.symbol == "mic.fill")
        let muted = QuickToggles.microphone(muted: true, settable: true)
        #expect(!muted.active && muted.symbol == "mic.slash.fill" && muted.help == "Mikrofon stumm")
    }

    @Test("Mikrofon ohne schreibbare Stummschaltung oder ohne Geraet: nicht klickbar")
    func microphoneDisabled() {
        let fixed = QuickToggles.microphone(muted: false, settable: false)
        #expect(!fixed.enabled && fixed.help == "Mikrofon an (nicht schaltbar)")
        #expect(QuickToggles.microphone(muted: nil, settable: true).enabled == false)
    }

    @Test("Bluetooth: Rune statt SF Symbol, immer klickbar (oeffnet Einstellungen)")
    func bluetooth() {
        #expect(QuickToggles.bluetooth(powerOn: true).symbol == nil)
        #expect(QuickToggles.bluetooth(powerOn: true).active)
        #expect(!QuickToggles.bluetooth(powerOn: false).active)
        #expect(!QuickToggles.bluetooth(powerOn: nil).active)
        #expect(QuickToggles.bluetooth(powerOn: nil).enabled)
    }

    @Test("Einstellungen leuchten nie")
    func settings() {
        #expect(!QuickToggles.settings.active && QuickToggles.settings.enabled)
    }

    @Test("Form: aus rund, an 12, gedrueckt 8", arguments: [
        (false, false, 24.0), (true, false, 12.0), (false, true, 8.0), (true, true, 8.0),
    ])
    func cornerRadius(active: Bool, pressed: Bool, radius: Double) {
        #expect(QuickToggles.cornerRadius(active: active, pressed: pressed, height: 48) == radius)
    }
}
