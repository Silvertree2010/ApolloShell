import ApolloShellCore
import Foundation
import Testing

@Suite("Sprachwahl und Neustart")
struct AppLanguageTests {
    @Test("AppleLanguages je Sprache", arguments: [
        (AppLanguage.system, nil), (.german, ["de"]), (.english, ["en"]),
    ] as [(AppLanguage, [String]?)])
    func appleLanguages(language: AppLanguage, expected: [String]?) {
        #expect(language.appleLanguages == expected)
    }

    @Test("Aus dem gespeicherten Wert lesen", arguments: [
        (["de"], AppLanguage.german), (["en"], .english), (nil, .system),
        ([], .system), (["fr"], .system), (["en", "de"], .english),
    ] as [([String]?, AppLanguage)])
    func fromStored(stored: [String]?, expected: AppLanguage) {
        #expect(AppLanguage(appleLanguages: stored) == expected)
    }

    @Test("launchd-Label aus XPC_SERVICE_NAME", arguments: [
        ("org.example.apolloshell", "org.example.apolloshell"),
        ("0", nil), ("", nil), (nil, nil),
        ("application.io.github.example.123.456", nil),
    ] as [(String?, String?)])
    func launchdLabel(value: String?, expected: String?) {
        let environment = value.map { ["XPC_SERVICE_NAME": $0] } ?? [:]
        #expect(AppRestart.launchdLabel(environment: environment) == expected)
    }

    @Test("Plan: launchd, wenn vorhanden, sonst neu oeffnen")
    func plan() {
        #expect(AppRestart.plan(environment: ["XPC_SERVICE_NAME": "org.example.apolloshell"], bundlePath: "/Applications/ApolloShell.app")
            == .launchd(label: "org.example.apolloshell"))
        #expect(AppRestart.plan(environment: [:], bundlePath: "/Applications/ApolloShell.app")
            == .relaunch(bundlePath: "/Applications/ApolloShell.app"))
    }

    @Test("launchctl-Argumente")
    func launchctlArguments() {
        #expect(AppRestart.launchctlArguments(label: "org.example.apolloshell", uid: 501)
            == ["kickstart", "-k", "gui/501/org.example.apolloshell"])
    }

    @Test("Neu-oeffnen-Befehl")
    func relaunchCommand() {
        #expect(AppRestart.relaunchCommand(bundlePath: "/Applications/ApolloShell.app")
            == "sleep 1; open -n \"/Applications/ApolloShell.app\" --args --relaunch")
    }
}
