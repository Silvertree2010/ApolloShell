import Foundation
import ApolloShellCore

public struct ConfigPaths: Sendable, Hashable {
    public var builtinConfigs: URL
    public var userConfig: URL
    public var applicationSupport: URL

    public init(builtinConfigs: URL, userConfig: URL, applicationSupport: URL) {
        self.builtinConfigs = builtinConfigs
        self.userConfig = userConfig
        self.applicationSupport = applicationSupport
    }

    public static func standard(environment: [String: String], home: URL, bundleResources: URL) -> ConfigPaths {
        let configHome: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty, xdg.hasPrefix("/") {
            configHome = URL(fileURLWithPath: xdg).appendingPathComponent("apolloshell")
        } else {
            configHome = home.appendingPathComponent(".config").appendingPathComponent("apolloshell")
        }
        let applicationSupport = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("ApolloShell")
        return ConfigPaths(
            builtinConfigs: bundleResources.appendingPathComponent("configs"),
            userConfig: configHome,
            applicationSupport: applicationSupport
        )
    }

    public var settingsFile: URL {
        userConfig.appendingPathComponent("settings.kdl")
    }

    public var stateDirectory: URL {
        userConfig.appendingPathComponent("state")
    }

    public var themesDirectory: URL {
        userConfig.appendingPathComponent("themes")
    }

    public var legacyThemesDirectory: URL {
        applicationSupport.appendingPathComponent(ThemeLoader.folderName, isDirectory: true)
    }

    public var packagesDirectory: URL {
        userConfig.appendingPathComponent("packages")
    }

    public func configRoot(for id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        if id == "user" {
            return userConfig
        }
        return userConfig.appendingPathComponent("configs").appendingPathComponent(id)
    }
}
