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

    @Test("Regel ohne Passwort: nur die zwei pmset-Befehle, nur fuer diesen Nutzer")
    func sudoersRule() throws {
        let rule = try #require(LidAwake.sudoersRule(user: "alex"))
        let lines = rule.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        #expect(lines == ["alex ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"])
        // Muss genau zu dem passen, was die App mit sudo -n aufruft.
        #expect(rule.contains(LidAwake.sudoArguments(disableSleep: true).dropFirst().joined(separator: " ")))
        #expect(rule.contains(LidAwake.sudoArguments(disableSleep: false).dropFirst().joined(separator: " ")))
        // Landet in einfachen Anfuehrungszeichen der Shell und in einem AppleScript-String.
        #expect(!rule.contains("'") && !rule.contains("\"") && !rule.contains("\\"))
    }

    @Test("Nutzernamen, die nicht in eine sudoers-Zeile duerfen", arguments: [
        "", "root ALL", "a,b", "a\nb", "a'b", "a\"b", "%admin", "-n", "a:b", "a=b", "ä",
    ])
    func unsafeUserNames(name: String) {
        #expect(LidAwake.sudoersRule(user: name) == nil)
        #expect(LidAwake.osascriptArguments(disableSleep: true, installRuleFor: name)
            == LidAwake.osascriptArguments(disableSleep: true))
    }

    @Test("gewoehnliche Kurznamen", arguments: ["alex", "a.b", "a_b", "a-b", "user2", "_www"])
    func safeUserNames(name: String) {
        #expect(LidAwake.sudoersRule(user: name) != nil)
    }

    @Test("Einschalten mit Regel: erst pmset, dann die gepruefte Regel an ihren Platz")
    func adminScriptWithRule() throws {
        let script = try #require(LidAwake.osascriptArguments(disableSleep: true, installRuleFor: "alex").last)
        #expect(script.hasPrefix("do shell script \"/usr/bin/pmset -a disablesleep 1 && "))
        #expect(script.contains("/usr/sbin/visudo -cf"))
        #expect(script.contains(LidAwake.sudoersFile))
        #expect(script.hasSuffix("with administrator privileges"))
        // Die Regel wird erst nach bestandener Pruefung verschoben.
        let visudo = try #require(script.range(of: "visudo -cf"))
        let move = try #require(script.range(of: "/bin/mv -f"))
        #expect(visudo.lowerBound < move.lowerBound)
        // Ausschalten richtet nie eine Regel ein.
        #expect(LidAwake.osascriptArguments(disableSleep: false, installRuleFor: "alex")
            == LidAwake.osascriptArguments(disableSleep: false))
    }

    @Test("Regel entfernen")
    func removeRuleScript() throws {
        let script = try #require(LidAwake.removeRuleArguments().last)
        #expect(script.hasPrefix("do shell script \"/bin/rm -f \(LidAwake.sudoersFile)\""))
        #expect(script.hasSuffix("with administrator privileges"))
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
