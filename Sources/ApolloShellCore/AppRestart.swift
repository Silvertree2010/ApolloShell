import Foundation

public enum AppRestart {
    public enum Plan: Equatable, Sendable {
        case launchd(label: String)
        case relaunch(bundlePath: String)
    }

    public static func launchdLabel(environment: [String: String]) -> String? {
        OnboardingAutostart.launchdLabel(environment: environment)
    }

    public static func plan(environment: [String: String], bundlePath: String) -> Plan {
        if let label = launchdLabel(environment: environment) { return .launchd(label: label) }
        return .relaunch(bundlePath: bundlePath)
    }

    public static func launchctlArguments(label: String, uid: Int32) -> [String] {
        ["kickstart", "-k", "gui/\(uid)/\(label)"]
    }

    public static func relaunchCommand(bundlePath: String) -> String {
        "sleep 1; open -n \"\(bundlePath)\" --args \(SingleInstance.relaunchArgument)"
    }
}
