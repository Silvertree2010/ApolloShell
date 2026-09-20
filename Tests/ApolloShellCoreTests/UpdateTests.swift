import ApolloShellCore
import Foundation
import Testing

@Suite("Updates: comparing versions")
struct AppVersionTests {
    @Test("Numbers from left to right")
    func ordersNumbers() {
        #expect(AppVersion("0.1.2")! > AppVersion("0.1.1")!)
        #expect(AppVersion("0.2.0")! > AppVersion("0.1.9")!)
        #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        #expect(AppVersion("0.1.10")! > AppVersion("0.1.9")!)
    }

    @Test("Missing places count as 0")
    func padsMissingParts() {
        #expect(AppVersion("0.1") == AppVersion("0.1.0"))
        #expect(!(AppVersion("0.1")! < AppVersion("0.1.0")!))
        #expect(AppVersion("2") == AppVersion("2.0.0"))
    }

    @Test("Tag notation and build metadata")
    func readsTagsAndBuildMetadata() {
        #expect(AppVersion("v0.1.2") == AppVersion("0.1.2"))
        #expect(AppVersion("0.1.2+35") == AppVersion("0.1.2"))
    }

    @Test("Pre-release sorts before the final one")
    func prereleaseSortsBefore() {
        #expect(AppVersion("0.2.0-beta.1")! < AppVersion("0.2.0")!)
        #expect(AppVersion("0.2.0-beta.2")! > AppVersion("0.2.0-beta.1")!)
        #expect(AppVersion("0.2.0-beta.1")! > AppVersion("0.1.9")!)
    }

    @Test("No number, no version")
    func rejectsNonsense() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("v") == nil)
        #expect(AppVersion("0.x.1") == nil)
        #expect(AppVersion("-1.0") == nil)
    }

    @Test("Text stays readable")
    func printsBack() {
        #expect(AppVersion("v0.1.2")?.description == "0.1.2")
        #expect(AppVersion("0.2.0-beta.1")?.description == "0.2.0-beta.1")
    }
}

@Suite("Updates: origin of the installation")
struct InstallKindTests {
    private let resources = URL(fileURLWithPath: "/Applications/ApolloShell.app/Contents/Resources")

    @Test("Marker file present: Homebrew")
    func detectsHomebrew() {
        let marker = resources.appendingPathComponent(InstallKind.markerName)
        let kind = InstallKind.detect(resourcesURL: resources) { $0 == marker }
        #expect(kind == .homebrew)
        #expect(!kind.updatesItself)
    }

    @Test("No marker: from the DMG, allowed to update itself")
    func detectsDisk() {
        let kind = InstallKind.detect(resourcesURL: resources) { _ in false }
        #expect(kind == .disk)
        #expect(kind.updatesItself)
    }

    @Test("No bundle (swift run): like DMG")
    func detectsWithoutBundle() {
        #expect(InstallKind.detect(resourcesURL: nil) { _ in true } == .disk)
    }
}

@Suite("Updates: reading the response from GitHub")
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

    @Test("Version and page from the response")
    func readsRelease() throws {
        let release = try #require(UpdateCheck.release(from: response(tag: "v0.1.2")))
        #expect(release.version == AppVersion("0.1.2"))
        #expect(release.page.absoluteString.hasSuffix("/releases/tag/v0.1.2"))
    }

    @Test("Draft and pre-release don't count")
    func skipsDraftAndPrerelease() {
        #expect(UpdateCheck.release(from: response(tag: "v0.2.0", draft: true)) == nil)
        #expect(UpdateCheck.release(from: response(tag: "v0.2.0", prerelease: true)) == nil)
    }

    @Test("Nonsense yields nothing")
    func rejectsGarbage() {
        #expect(UpdateCheck.release(from: Data("not json".utf8)) == nil)
        #expect(UpdateCheck.release(from: Data("{}".utf8)) == nil)
    }

    @Test("A newer version is reported")
    func reportsNewer() async throws {
        let check = UpdateCheck(url: UpdateCheck.latestReleaseURL) { _ in self.response(tag: "v0.1.2") }
        let outcome = await check.run(current: AppVersion("0.1.1"))
        guard case let .newer(release) = outcome else {
            Issue.record("expected: newer version, got: \(outcome)")
            return
        }
        #expect(release.version == AppVersion("0.1.2"))
    }

    @Test("Same or older version: current")
    func reportsCurrent() async {
        let check = UpdateCheck(url: UpdateCheck.latestReleaseURL) { _ in self.response(tag: "v0.1.1") }
        #expect(await check.run(current: AppVersion("0.1.1")) == .current)
        #expect(await check.run(current: AppVersion("0.2.0")) == .current)
    }

    @Test("Network error is reported, not swallowed")
    func reportsFailure() async {
        struct Offline: Error {}
        let check = UpdateCheck(url: UpdateCheck.latestReleaseURL) { _ in throw Offline() }
        guard case .failed = await check.run(current: AppVersion("0.1.1")) else {
            Issue.record("expected: failed")
            return
        }
    }
}

@Suite("Updates: settings")
struct UpdateSettingsTests {
    @Test("Default: both on")
    func defaultsAreOn() {
        let settings = UpdateSettings()
        #expect(settings.checkAutomatically)
        #expect(settings.installAutomatically)
    }

    @Test("File without the section: defaults, rest stays")
    func missingSectionKeepsDefaults() {
        let data = Data(#"{"bar": {"screens": "all"}}"#.utf8)
        let settings = ShellSettings.load(from: data)
        #expect(settings.updates == UpdateSettings())
        #expect(settings.theme.name == nil)
    }

    @Test("Partial data: only the missing switch falls back to the default")
    func partialSectionIsLenient() {
        let data = Data(#"{"updates": {"installAutomatically": false}}"#.utf8)
        let settings = ShellSettings.load(from: data)
        #expect(settings.updates.checkAutomatically)
        #expect(!settings.updates.installAutomatically)
    }

    @Test("Nonsense in the switch: default")
    func wrongTypeFallsBack() {
        let data = Data(#"{"updates": {"checkAutomatically": "maybe"}}"#.utf8)
        #expect(ShellSettings.load(from: data).updates.checkAutomatically)
    }

    @Test("There and back")
    func roundTrips() {
        var settings = ShellSettings()
        settings.updates = UpdateSettings(checkAutomatically: false, installAutomatically: false)
        settings.theme = ThemeSettings(name: "Mitternacht.css")
        let again = ShellSettings.load(from: settings.encoded())
        #expect(again.updates == settings.updates)
        #expect(again.theme == settings.theme)
    }

    @Test("Theme name with a path component is rejected")
    func themeNameStaysInsideFolder() {
        #expect(ShellSettings.load(from: Data(#"{"theme": {"name": "../../etc/passwd"}}"#.utf8)).theme.name == nil)
        #expect(ShellSettings.load(from: Data(#"{"theme": {"name": ".hidden"}}"#.utf8)).theme.name == nil)
        #expect(ShellSettings.load(from: Data(#"{"theme": {"name": "  "}}"#.utf8)).theme.name == nil)
        #expect(ShellSettings.load(from: Data(#"{"theme": {"name": "Mitternacht"}}"#.utf8)).theme.name == "Mitternacht")
    }
}
