import ApolloShellCore
import Foundation
import Testing

@Suite("Updates: Versionen vergleichen")
struct AppVersionTests {
    @Test("Zahlen von links nach rechts")
    func ordersNumbers() {
        #expect(AppVersion("0.1.2")! > AppVersion("0.1.1")!)
        #expect(AppVersion("0.2.0")! > AppVersion("0.1.9")!)
        #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        #expect(AppVersion("0.1.10")! > AppVersion("0.1.9")!)
    }

    @Test("Fehlende Stellen zaehlen als 0")
    func padsMissingParts() {
        #expect(AppVersion("0.1") == AppVersion("0.1.0"))
        #expect(!(AppVersion("0.1")! < AppVersion("0.1.0")!))
        #expect(AppVersion("2") == AppVersion("2.0.0"))
    }

    @Test("Tag-Schreibweise und Baumetadaten")
    func readsTagsAndBuildMetadata() {
        #expect(AppVersion("v0.1.2") == AppVersion("0.1.2"))
        #expect(AppVersion("0.1.2+35") == AppVersion("0.1.2"))
    }

    @Test("Vorabfassung steht vor der fertigen")
    func prereleaseSortsBefore() {
        #expect(AppVersion("0.2.0-beta.1")! < AppVersion("0.2.0")!)
        #expect(AppVersion("0.2.0-beta.2")! > AppVersion("0.2.0-beta.1")!)
        #expect(AppVersion("0.2.0-beta.1")! > AppVersion("0.1.9")!)
    }

    @Test("Ohne Zahl keine Version")
    func rejectsNonsense() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("v") == nil)
        #expect(AppVersion("0.x.1") == nil)
        #expect(AppVersion("-1.0") == nil)
    }

    @Test("Text bleibt lesbar")
    func printsBack() {
        #expect(AppVersion("v0.1.2")?.description == "0.1.2")
        #expect(AppVersion("0.2.0-beta.1")?.description == "0.2.0-beta.1")
    }
}

@Suite("Updates: Herkunft der Installation")
struct InstallKindTests {
    private let resources = URL(fileURLWithPath: "/Applications/ApolloShell.app/Contents/Resources")

    @Test("Markierungsdatei da: Homebrew")
    func detectsHomebrew() {
        let marker = resources.appendingPathComponent(InstallKind.markerName)
        let kind = InstallKind.detect(resourcesURL: resources) { $0 == marker }
        #expect(kind == .homebrew)
        #expect(!kind.updatesItself)
    }

    @Test("Ohne Markierung: aus dem DMG, darf sich selbst erneuern")
    func detectsDisk() {
        let kind = InstallKind.detect(resourcesURL: resources) { _ in false }
        #expect(kind == .disk)
        #expect(kind.updatesItself)
    }

    @Test("Ohne Bundle (swift run): wie DMG")
    func detectsWithoutBundle() {
        #expect(InstallKind.detect(resourcesURL: nil) { _ in true } == .disk)
    }
}

@Suite("Updates: Antwort von GitHub lesen")
struct UpdateCheckTests {
    private func response(tag: String, draft: Bool = false, prerelease: Bool = false) -> Data {
        let json: [String: Any] = [
            "tag_name": tag,
            "html_url": "https://github.com/Silvertree2010/ApolloShell/releases/tag/\(tag)",
            "draft": draft,
            "prerelease": prerelease,
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test("Fassung und Seite aus der Antwort")
    func readsRelease() throws {
        let release = try #require(UpdateCheck.release(from: response(tag: "v0.1.2")))
        #expect(release.version == AppVersion("0.1.2"))
        #expect(release.page.absoluteString.hasSuffix("/releases/tag/v0.1.2"))
    }

    @Test("Entwurf und Vorabfassung zaehlen nicht")
    func skipsDraftAndPrerelease() {
        #expect(UpdateCheck.release(from: response(tag: "v0.2.0", draft: true)) == nil)
        #expect(UpdateCheck.release(from: response(tag: "v0.2.0", prerelease: true)) == nil)
    }

    @Test("Unsinn ergibt nichts")
    func rejectsGarbage() {
        #expect(UpdateCheck.release(from: Data("kein json".utf8)) == nil)
        #expect(UpdateCheck.release(from: Data("{}".utf8)) == nil)
    }

    @Test("Neuere Fassung wird gemeldet")
    func reportsNewer() async throws {
        let check = UpdateCheck(url: UpdateCheck.latestReleaseURL) { _ in self.response(tag: "v0.1.2") }
        let outcome = await check.run(current: AppVersion("0.1.1"))
        guard case let .newer(release) = outcome else {
            Issue.record("erwartet: neuere Fassung, bekommen: \(outcome)")
            return
        }
        #expect(release.version == AppVersion("0.1.2"))
    }

    @Test("Gleiche oder aeltere Fassung: aktuell")
    func reportsCurrent() async {
        let check = UpdateCheck(url: UpdateCheck.latestReleaseURL) { _ in self.response(tag: "v0.1.1") }
        #expect(await check.run(current: AppVersion("0.1.1")) == .current)
        #expect(await check.run(current: AppVersion("0.2.0")) == .current)
    }

    @Test("Netzfehler wird gemeldet, nicht verschluckt")
    func reportsFailure() async {
        struct Offline: Error {}
        let check = UpdateCheck(url: UpdateCheck.latestReleaseURL) { _ in throw Offline() }
        guard case .failed = await check.run(current: AppVersion("0.1.1")) else {
            Issue.record("erwartet: fehlgeschlagen")
            return
        }
    }
}

@Suite("Updates: Einstellungen")
struct UpdateSettingsTests {
    @Test("Vorgabe: beides an")
    func defaultsAreOn() {
        let settings = UpdateSettings()
        #expect(settings.checkAutomatically)
        #expect(settings.installAutomatically)
    }

    @Test("Datei ohne den Abschnitt: Vorgaben, Rest bleibt")
    func missingSectionKeepsDefaults() {
        let data = Data(#"{"bar": {"screens": "all"}}"#.utf8)
        let settings = ShellSettings.load(from: data)
        #expect(settings.updates == UpdateSettings())
        #expect(settings.theme.name == nil)
    }

    @Test("Halbe Angaben: nur der fehlende Schalter faellt auf die Vorgabe")
    func partialSectionIsLenient() {
        let data = Data(#"{"updates": {"installAutomatically": false}}"#.utf8)
        let settings = ShellSettings.load(from: data)
        #expect(settings.updates.checkAutomatically)
        #expect(!settings.updates.installAutomatically)
    }

    @Test("Unsinn im Schalter: Vorgabe")
    func wrongTypeFallsBack() {
        let data = Data(#"{"updates": {"checkAutomatically": "vielleicht"}}"#.utf8)
        #expect(ShellSettings.load(from: data).updates.checkAutomatically)
    }

    @Test("Hin und zurueck")
    func roundTrips() {
        var settings = ShellSettings()
        settings.updates = UpdateSettings(checkAutomatically: false, installAutomatically: false)
        settings.theme = ThemeSettings(name: "Mitternacht.css")
        let again = ShellSettings.load(from: settings.encoded())
        #expect(again.updates == settings.updates)
        #expect(again.theme == settings.theme)
    }

    @Test("Theme-Name mit Pfadanteil wird verworfen")
    func themeNameStaysInsideFolder() {
        #expect(ShellSettings.load(from: Data(#"{"theme": {"name": "../../etc/passwd"}}"#.utf8)).theme.name == nil)
        #expect(ShellSettings.load(from: Data(#"{"theme": {"name": ".hidden"}}"#.utf8)).theme.name == nil)
        #expect(ShellSettings.load(from: Data(#"{"theme": {"name": "  "}}"#.utf8)).theme.name == nil)
        #expect(ShellSettings.load(from: Data(#"{"theme": {"name": "Mitternacht"}}"#.utf8)).theme.name == "Mitternacht")
    }
}
