import ApolloShellCore
import Foundation
import Testing

@Suite("Stay awake even with the lid closed")
struct LidAwakeTests {
    @Test("Reading SleepDisabled from pmset -g")
    func parse() {
        let on = "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n standby              1\n"
        let off = " SleepDisabled\t\t0\n sleep                1\n"
        #expect(LidAwake.sleepDisabled(pmsetOutput: on) == true)
        #expect(LidAwake.sleepDisabled(pmsetOutput: off) == false)
        #expect(LidAwake.sleepDisabled(pmsetOutput: " sleep 1\n") == nil)
    }

    @Test("Battery protection only on battery power and from 10 %")
    func batteryGuard() {
        #expect(LidAwake.shouldStop(battery: BatteryState(level: 10, charging: false, onAC: false)))
        #expect(LidAwake.shouldStop(battery: BatteryState(level: 4, charging: false, onAC: false)))
        #expect(!LidAwake.shouldStop(battery: BatteryState(level: 11, charging: false, onAC: false)))
        #expect(!LidAwake.shouldStop(battery: BatteryState(level: 5, charging: true, onAC: true)))
        #expect(!LidAwake.shouldStop(battery: nil))
    }

    @Test("Setting: off on a fresh install, on for existing ones", arguments: [
        (nil, false),
        ("{}", true),
        ("broken", true),
        (#"{"toasts":{"batteryWarnings":false}}"#, true),
        (#"{"keepAwake":"ja"}"#, true),
        (#"{"keepAwake":{}}"#, false),
        (#"{"keepAwake":{"lidClosed":false}}"#, false),
        (#"{"keepAwake":{"lidClosed":true}}"#, true),
    ] as [(String?, Bool)])
    func lidSettingMigration(json: String?, lidClosed: Bool) {
        #expect(ShellSettings.load(from: json.map { Data($0.utf8) }).keepAwake.lidClosed == lidClosed)
    }

    @Test("Setting survives writing and reading", arguments: [true, false])
    func lidSettingRoundTrip(lidClosed: Bool) {
        var settings = ShellSettings.firstLaunch
        settings.keepAwake.lidClosed = lidClosed
        #expect(ShellSettings.load(from: settings.encoded()).keepAwake.lidClosed == lidClosed)
    }

    @Test("sudo -n without a prompt", arguments: [
        (true, ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"]),
        (false, ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]),
    ])
    func sudoArguments(on: Bool, expected: [String]) {
        #expect(LidAwake.sudoArguments(disableSleep: on) == expected)
    }

    @Test("Administrator prompt through AppleScript", arguments: [
        (true, "do shell script \"/usr/bin/pmset -a disablesleep 1\"", "suspend sleep"),
        (false, "do shell script \"/usr/bin/pmset -a disablesleep 0\"", "allow sleep"),
    ])
    func adminScript(on: Bool, command: String, reason: String) {
        let arguments = LidAwake.osascriptArguments(disableSleep: on)
        #expect(arguments.first == "-e")
        #expect(arguments.last?.hasPrefix(command) == true)
        #expect(arguments.last?.hasSuffix("with administrator privileges") == true)
        #expect(arguments.last?.contains(reason) == true)
    }

    @Test("Rule without a password: only the two pmset commands, only for this user")
    func sudoersRule() throws {
        let rule = try #require(LidAwake.sudoersRule(user: "alex"))
        let lines = rule.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        #expect(lines == ["alex ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"])
        // Must match exactly what the app invokes via sudo -n.
        #expect(rule.contains(LidAwake.sudoArguments(disableSleep: true).dropFirst().joined(separator: " ")))
        #expect(rule.contains(LidAwake.sudoArguments(disableSleep: false).dropFirst().joined(separator: " ")))
        // Ends up in single quotes for the shell and in an AppleScript string.
        #expect(!rule.contains("'") && !rule.contains("\"") && !rule.contains("\\"))
    }

    @Test("User names that must not go into a sudoers line", arguments: [
        "", "root ALL", "a,b", "a\nb", "a'b", "a\"b", "%admin", "-n", "a:b", "a=b", "ä",
    ])
    func unsafeUserNames(name: String) {
        #expect(LidAwake.sudoersRule(user: name) == nil)
        #expect(LidAwake.osascriptArguments(disableSleep: true, installRuleFor: name)
            == LidAwake.osascriptArguments(disableSleep: true))
    }

    @Test("ordinary short names", arguments: ["alex", "a.b", "a_b", "a-b", "user2", "_www"])
    func safeUserNames(name: String) {
        #expect(LidAwake.sudoersRule(user: name) != nil)
    }

    @Test("Turning on with a rule: pmset first, then the checked rule moved into place")
    func adminScriptWithRule() throws {
        let script = try #require(LidAwake.osascriptArguments(disableSleep: true, installRuleFor: "alex").last)
        #expect(script.hasPrefix("do shell script \"/usr/bin/pmset -a disablesleep 1 && "))
        #expect(script.contains("/usr/sbin/visudo -cf"))
        #expect(script.contains(LidAwake.sudoersFile))
        #expect(script.hasSuffix("with administrator privileges"))
        // The rule is only moved after passing the check.
        let visudo = try #require(script.range(of: "visudo -cf"))
        let move = try #require(script.range(of: "/bin/mv -f"))
        #expect(visudo.lowerBound < move.lowerBound)
        // Turning off never installs a rule.
        #expect(LidAwake.osascriptArguments(disableSleep: false, installRuleFor: "alex")
            == LidAwake.osascriptArguments(disableSleep: false))
    }

    @Test("Removing the rule")
    func removeRuleScript() throws {
        let script = try #require(LidAwake.removeRuleArguments().last)
        #expect(script.hasPrefix("do shell script \"/bin/rm -f \(LidAwake.sudoersFile)\""))
        #expect(script.hasSuffix("with administrator privileges"))
    }

    @Test("Subtitle per state of the lid part", arguments: [
        (KeepAwakeLid.off, ""),
        (KeepAwakeLid.on, " · also with lid closed"),
        (KeepAwakeLid.pending, " · waiting for approval"),
        (KeepAwakeLid.declined, " · only with lid open"),
    ])
    func lidSubtitle(lid: KeepAwakeLid, suffix: String) {
        let now = Date()
        let base = KeepAwakeText.subtitle(since: now, now: now, lid: .off)
        #expect(KeepAwakeText.subtitle(since: now, now: now, lid: lid) == base + suffix)
        #expect(KeepAwakeText.subtitle(since: nil, now: now, lid: lid) == KeepAwakeText.inactive)
    }

    @Test("The subtitle says that it holds with the lid closed too")
    func subtitle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let since = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 14, minute: 30))!
        let now = since.addingTimeInterval(600)
        #expect(KeepAwakeText.subtitle(since: since, now: now, lidClosed: true, calendar: calendar)
            == "Active since 14:30 · also with lid closed")
        #expect(KeepAwakeText.subtitle(since: since, now: now, calendar: calendar) == "Active since 14:30")
    }
}
