import ApolloShellCore
import Foundation
import Testing

@Suite("Einstellungen: Version, Import, Zuruecksetzen")
struct ShellSettingsVersionTests {
    @Test("alte Datei ohne Version wird auf die aktuelle gehoben")
    func migrate() throws {
        let s = try JSONDecoder().decode(ShellSettings.self, from: Data("{\"bar\":{}}".utf8))
        #expect(s.version == ShellSettings.currentVersion)
        let back = try JSONSerialization.jsonObject(with: s.encoded()) as? [String: Any]
        #expect(back?["version"] as? Int == ShellSettings.currentVersion)
    }

    @Test("Import nimmt nur ein JSON-Objekt mit Inhalt")
    func importing() {
        #expect(ShellSettings.importing(Data("nope".utf8)) == nil)
        #expect(ShellSettings.importing(Data("[]".utf8)) == nil)
        #expect(ShellSettings.importing(Data("{}".utf8)) == nil)
        #expect(ShellSettings.importing(ShellSettings().encoded()) != nil)
    }

    @Test("Alles zuruecksetzen behaelt Einfuehrung und Absturzberichte")
    func restored() {
        var s = ShellSettings()
        s.toasts.batteryWarnings = false
        let r = s.restored
        #expect(r.onboarding == s.onboarding)
        #expect(r.crashReports == s.crashReports)
        #expect(r.toasts.batteryWarnings)
    }
}
