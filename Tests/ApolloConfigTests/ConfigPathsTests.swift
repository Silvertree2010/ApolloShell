import Testing
import Foundation
@testable import ApolloConfig

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
}
