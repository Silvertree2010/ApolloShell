import ApolloShellCore
import Foundation
import Testing

@Suite("Wach halten auch zugeklappt")
struct LidAwakeTests {
    @Test("SleepDisabled aus pmset -g lesen")
    func parse() {
        let on = "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n standby              1\n"
        let off = " SleepDisabled\t\t0\n sleep                1\n"
        #expect(LidAwake.sleepDisabled(pmsetOutput: on) == true)
        #expect(LidAwake.sleepDisabled(pmsetOutput: off) == false)
        #expect(LidAwake.sleepDisabled(pmsetOutput: " sleep 1\n") == nil)
    }

    @Test("Akku-Schutz nur im Akkubetrieb und ab 10 %")
    func batteryGuard() {
        #expect(LidAwake.shouldStop(battery: BatteryState(level: 10, charging: false, onAC: false)))
        #expect(LidAwake.shouldStop(battery: BatteryState(level: 4, charging: false, onAC: false)))
        #expect(!LidAwake.shouldStop(battery: BatteryState(level: 11, charging: false, onAC: false)))
        #expect(!LidAwake.shouldStop(battery: BatteryState(level: 5, charging: true, onAC: true)))
        #expect(!LidAwake.shouldStop(battery: nil))
    }

    @Test("Einstellung: aus bei frischer Installation, an für vorhandene", arguments: [
        (nil, false),
        ("{}", true),
        ("kaputt", true),
        (#"{"toasts":{"batteryWarnings":false}}"#, true),
        (#"{"keepAwake":"ja"}"#, true),
        (#"{"keepAwake":{}}"#, false),
        (#"{"keepAwake":{"lidClosed":false}}"#, false),
        (#"{"keepAwake":{"lidClosed":true}}"#, true),
    ] as [(String?, Bool)])
    func lidSettingMigration(json: String?, lidClosed: Bool) {
        #expect(ShellSettings.load(from: json.map { Data($0.utf8) }).keepAwake.lidClosed == lidClosed)
    }

    @Test("Einstellung übersteht Schreiben und Lesen", arguments: [true, false])
    func lidSettingRoundTrip(lidClosed: Bool) {
        var settings = ShellSettings.firstLaunch
        settings.keepAwake.lidClosed = lidClosed
        #expect(ShellSettings.load(from: settings.encoded()).keepAwake.lidClosed == lidClosed)
    }

    @Test("sudo -n ohne Rückfrage", arguments: [
        (true, ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"]),
        (false, ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]),
    ])
    func sudoArguments(on: Bool, expected: [String]) {
        #expect(LidAwake.sudoArguments(disableSleep: on) == expected)
    }

    @Test("Administrator-Rückfrage über AppleScript", arguments: [
        (true, "do shell script \"/usr/bin/pmset -a disablesleep 1\"", "aussetzen"),
        (false, "do shell script \"/usr/bin/pmset -a disablesleep 0\"", "wieder erlauben"),
    ])
    func adminScript(on: Bool, command: String, reason: String) {
        let arguments = LidAwake.osascriptArguments(disableSleep: on)
        #expect(arguments.first == "-e")
        #expect(arguments.last?.hasPrefix(command) == true)
        #expect(arguments.last?.hasSuffix("with administrator privileges") == true)
        #expect(arguments.last?.contains(reason) == true)
    }

    @Test("Untertitel je Stand des Deckel-Teils", arguments: [
        (KeepAwakeLid.off, ""),
        (KeepAwakeLid.on, " · auch zugeklappt"),
        (KeepAwakeLid.pending, " · wartet auf Freigabe"),
        (KeepAwakeLid.declined, " · nur aufgeklappt"),
    ])
    func lidSubtitle(lid: KeepAwakeLid, suffix: String) {
        let now = Date()
        let base = KeepAwakeText.subtitle(since: now, now: now, lid: .off)
        #expect(KeepAwakeText.subtitle(since: now, now: now, lid: lid) == base + suffix)
        #expect(KeepAwakeText.subtitle(since: nil, now: now, lid: lid) == KeepAwakeText.inactive)
    }

    @Test("Untertitel sagt, dass es auch zugeklappt gilt")
    func subtitle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let since = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 14, minute: 30))!
        let now = since.addingTimeInterval(600)
        #expect(KeepAwakeText.subtitle(since: since, now: now, lidClosed: true, calendar: calendar)
            == "Aktiv seit 14:30 · auch zugeklappt")
        #expect(KeepAwakeText.subtitle(since: since, now: now, calendar: calendar) == "Aktiv seit 14:30")
    }
}
