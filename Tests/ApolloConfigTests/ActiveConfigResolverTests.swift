import Testing
import Foundation
@testable import ApolloConfig

@Suite("ActiveConfigResolver")
struct ActiveConfigResolverTests {
    static let builtin = URL(fileURLWithPath: "/Applications/ApolloShell.app/Contents/Resources/configs")
    static let user = URL(fileURLWithPath: "/Users/tester/.config/apolloshell")
    static let appSupport = URL(fileURLWithPath: "/Users/tester/Library/Application Support/ApolloShell")

    static func paths() -> ConfigPaths {
        ConfigPaths(builtinConfigs: builtin, userConfig: user, applicationSupport: appSupport)
    }

    static func fileSystem(_ files: [String: String]) -> MemoryFileSystem {
        MemoryFileSystem(files)
    }

    @Test("Startargument gewinnt immer")
    func cliOverrideWins() {
        let override = URL(fileURLWithPath: "/tmp/dev-config")
        let fileSystem = Self.fileSystem([:])
        let (location, diagnostics) = ActiveConfigResolver.resolve(cliOverride: override, settings: ShellSettingsFile(), paths: Self.paths(), fileSystem: fileSystem)
        #expect(location.id == "dev-config")
        #expect(location.root == override)
        #expect(location.isBuiltin == false)
        #expect(diagnostics.isEmpty)
    }

    @Test("settings.kdl nennt eine eingebaute Config")
    func settingsNamesBuiltin() {
        let fileSystem = Self.fileSystem(["\(Self.builtin.path)/launcher-only/shell.kdl": ""])
        let settings = ShellSettingsFile(config: "launcher-only")
        let (location, diagnostics) = ActiveConfigResolver.resolve(cliOverride: nil, settings: settings, paths: Self.paths(), fileSystem: fileSystem)
        #expect(location.id == "launcher-only")
        #expect(location.root.path == "\(Self.builtin.path)/launcher-only")
        #expect(location.isBuiltin)
        #expect(diagnostics.isEmpty)
    }

    @Test("settings.kdl nennt eine installierte Config")
    func settingsNamesInstalled() {
        let fileSystem = Self.fileSystem(["\(Self.user.path)/configs/mine/shell.kdl": ""])
        let settings = ShellSettingsFile(config: "mine")
        let (location, diagnostics) = ActiveConfigResolver.resolve(cliOverride: nil, settings: settings, paths: Self.paths(), fileSystem: fileSystem)
        #expect(location.id == "mine")
        #expect(location.root.path == "\(Self.user.path)/configs/mine")
        #expect(location.isBuiltin == false)
        #expect(diagnostics.isEmpty)
    }

    @Test("settings.kdl nennt user")
    func settingsNamesUser() {
        let fileSystem = Self.fileSystem(["\(Self.user.path)/shell.kdl": ""])
        let settings = ShellSettingsFile(config: "user")
        let (location, diagnostics) = ActiveConfigResolver.resolve(cliOverride: nil, settings: settings, paths: Self.paths(), fileSystem: fileSystem)
        #expect(location.id == "user")
        #expect(location.root == Self.user)
        #expect(diagnostics.isEmpty)
    }

    @Test("unbekannte Kennung faellt auf Default zurueck")
    func unknownIdentifierFallsBack() {
        let fileSystem = Self.fileSystem([:])
        let settings = ShellSettingsFile(config: "does-not-exist")
        let (location, diagnostics) = ActiveConfigResolver.resolve(cliOverride: nil, settings: settings, paths: Self.paths(), fileSystem: fileSystem)
        #expect(location.id == "apolloshell-default")
        #expect(location.isBuiltin)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test("shell.kdl im Config-Ordner ergibt user")
    func userShellFileWins() {
        let fileSystem = Self.fileSystem(["\(Self.user.path)/shell.kdl": ""])
        let (location, diagnostics) = ActiveConfigResolver.resolve(cliOverride: nil, settings: ShellSettingsFile(), paths: Self.paths(), fileSystem: fileSystem)
        #expect(location.id == "user")
        #expect(location.root == Self.user)
        #expect(diagnostics.isEmpty)
    }

    @Test("ohne alles laeuft apolloshell-default")
    func fallsBackToDefault() {
        let fileSystem = Self.fileSystem([:])
        let (location, diagnostics) = ActiveConfigResolver.resolve(cliOverride: nil, settings: ShellSettingsFile(), paths: Self.paths(), fileSystem: fileSystem)
        #expect(location.id == "apolloshell-default")
        #expect(location.isBuiltin)
        #expect(diagnostics.isEmpty)
    }
}
