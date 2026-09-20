import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Utilities panel: stay awake")
struct KeepAwakeTextTests {
    /// Fixed time zone so the test doesn't depend on the machine.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    @Test("off: normal power-saving mode")
    func inactive() {
        #expect(KeepAwakeText.subtitle(since: nil, now: date(14, 12, 0), calendar: calendar) == "Mac sleeps normally")
    }

    @Test("today: only the time, two digits")
    func today() {
        #expect(KeepAwakeText.subtitle(since: date(14, 14, 30), now: date(14, 15, 0), calendar: calendar) == "Active since 14:30")
        #expect(KeepAwakeText.subtitle(since: date(14, 0, 5), now: date(14, 9, 0), calendar: calendar) == "Active since 00:05")
    }

    @Test("across midnight: yesterday")
    func yesterday() {
        #expect(KeepAwakeText.subtitle(since: date(13, 23, 10), now: date(14, 7, 0), calendar: calendar) == "Active since yesterday, 23:10")
    }

    @Test("older: with date")
    func older() {
        #expect(KeepAwakeText.subtitle(since: date(9, 8, 4), now: date(14, 7, 0), calendar: calendar) == "Active since 09.09., 08:04")
    }
}

@Suite("Utilities panel: quick toggles")
struct QuickTogglesTests {
    @Test("Wi-Fi: on lights up, off doesn't, not clickable without an interface")
    func wifi() {
        #expect(QuickToggles.wifi(powerOn: true) == QuickToggleLook(symbol: "wifi", active: true, enabled: true, help: "Wi-Fi On"))
        #expect(QuickToggles.wifi(powerOn: false).active == false)
        #expect(QuickToggles.wifi(powerOn: false).symbol == "wifi.slash")
        #expect(QuickToggles.wifi(powerOn: nil).enabled == false)
    }

    @Test("Microphone lights up as long as it is NOT muted (like Caelestia)")
    func microphone() {
        let live = QuickToggles.microphone(muted: false, settable: true)
        #expect(live.active && live.enabled && live.symbol == "mic.fill")
        let muted = QuickToggles.microphone(muted: true, settable: true)
        #expect(!muted.active && muted.symbol == "mic.slash.fill" && muted.help == "Microphone Muted")
    }

    @Test("Microphone without a writable mute or without a device: not clickable")
    func microphoneDisabled() {
        let fixed = QuickToggles.microphone(muted: false, settable: false)
        #expect(!fixed.enabled && fixed.help == "Microphone On (not switchable)")
        #expect(QuickToggles.microphone(muted: nil, settable: true).enabled == false)
    }

    @Test("Bluetooth: rune instead of SF Symbol, always clickable (opens settings)")
    func bluetooth() {
        #expect(QuickToggles.bluetooth(powerOn: true).symbol == nil)
        #expect(QuickToggles.bluetooth(powerOn: true).active)
        #expect(!QuickToggles.bluetooth(powerOn: false).active)
        #expect(!QuickToggles.bluetooth(powerOn: nil).active)
        #expect(QuickToggles.bluetooth(powerOn: nil).enabled)
    }

    @Test("Settings never lights up")
    func settings() {
        #expect(!QuickToggles.settings.active && QuickToggles.settings.enabled)
    }

    @Test("Shape: off round, on 12, pressed 8", arguments: [
        (false, false, 24.0), (true, false, 12.0), (false, true, 8.0), (true, true, 8.0),
    ])
    func cornerRadius(active: Bool, pressed: Bool, radius: Double) {
        #expect(QuickToggles.cornerRadius(active: active, pressed: pressed, height: 48) == radius)
    }
}
