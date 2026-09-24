import Testing
import Foundation
@testable import ApolloConfig
import ApolloShellCore

@Suite("ConfigPaths")
struct ConfigPathsTests {
    @Test("XDG_CONFIG_HOME wird bevorzugt")
    func honorsXDGConfigHome() {
        let paths = ConfigPaths.standard(
            environment: ["XDG_CONFIG_HOME": "/custom"],
            home: URL(fileURLWithPath: "/Users/tester"),
            bundleResources: URL(fileURLWithPath: "/Applications/ApolloShell.app/Contents/Resources")
        )
        #expect(paths.userConfig.path == "/custom/apolloshell")
        #expect(paths.settingsFile.path == "/custom/apolloshell/settings.kdl")
        #expect(paths.stateDirectory.path == "/custom/apolloshell/state")
        #expect(paths.builtinConfigs.path == "/Applications/ApolloShell.app/Contents/Resources/configs")
    }

    @Test("Ohne XDG_CONFIG_HOME faellt auf ~/.config/apolloshell zurueck")
    func fallsBackToHomeConfig() {
        let paths = ConfigPaths.standard(
            environment: [:],
            home: URL(fileURLWithPath: "/Users/tester"),
            bundleResources: URL(fileURLWithPath: "/Applications/ApolloShell.app/Contents/Resources")
        )
        #expect(paths.userConfig.path == "/Users/tester/.config/apolloshell")
        #expect(paths.applicationSupport.path == "/Users/tester/Library/Application Support/ApolloShell")
    }

    @Test("configRoot fuer user und andere Kennungen")
    func configRootMapping() {
        let paths = ConfigPaths(
            builtinConfigs: URL(fileURLWithPath: "/builtin"),
            userConfig: URL(fileURLWithPath: "/config"),
            applicationSupport: URL(fileURLWithPath: "/support")
        )
        #expect(paths.configRoot(for: "user")?.path == "/config")
        #expect(paths.configRoot(for: "mine")?.path == "/config/configs/mine")
        #expect(paths.configRoot(for: "") == nil)
    }

    @Test("legacyThemesDirectory nutzt ThemeLoader.folderName")
    func legacyThemesDirectoryMatchesThemeLoaderFolderName() {
        let paths = ConfigPaths(
            builtinConfigs: URL(fileURLWithPath: "/builtin"),
            userConfig: URL(fileURLWithPath: "/config"),
            applicationSupport: URL(fileURLWithPath: "/Users/tester/Library/Application Support/ApolloShell")
        )
        let expected = URL(fileURLWithPath: "/Users/tester/Library/Application Support/ApolloShell")
            .appendingPathComponent(ThemeLoader.folderName, isDirectory: true)
        #expect(paths.legacyThemesDirectory.path == expected.path)
        #expect(paths.legacyThemesDirectory.path == "/Users/tester/Library/Application Support/ApolloShell/themes")
    }

    @Test("Leeres XDG_CONFIG_HOME wird ignoriert")
    func ignoresEmptyXDGConfigHome() {
        let paths = ConfigPaths.standard(
            environment: ["XDG_CONFIG_HOME": ""],
            home: URL(fileURLWithPath: "/Users/tester"),
            bundleResources: URL(fileURLWithPath: "/Applications/ApolloShell.app/Contents/Resources")
        )
        #expect(paths.userConfig.path == "/Users/tester/.config/apolloshell")
    }

    @Test("Relatives XDG_CONFIG_HOME wird ignoriert")
    func ignoresRelativeXDGConfigHome() {
        let paths = ConfigPaths.standard(
            environment: ["XDG_CONFIG_HOME": "relative/path"],
            home: URL(fileURLWithPath: "/Users/tester"),
            bundleResources: URL(fileURLWithPath: "/Applications/ApolloShell.app/Contents/Resources")
        )
        #expect(paths.userConfig.path == "/Users/tester/.config/apolloshell")
    }

    @Test("Absolutes XDG_CONFIG_HOME wird verwendet")
    func honorsAbsoluteXDGConfigHome() {
        let paths = ConfigPaths.standard(
            environment: ["XDG_CONFIG_HOME": "/custom"],
            home: URL(fileURLWithPath: "/Users/tester"),
            bundleResources: URL(fileURLWithPath: "/Applications/ApolloShell.app/Contents/Resources")
        )
        #expect(paths.userConfig.path == "/custom/apolloshell")
    }
}
