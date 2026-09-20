import Foundation

/// A restart of the app, so that a new setting holds.
///
/// Two ways, depending on who started the process:
/// - A launchd agent of our own (macOS then sets `XPC_SERVICE_NAME` to its
///   label): `launchctl kickstart -k` starts it again.
/// - Otherwise (Finder, `open`, a development build): a helper process waits
///   briefly, so that the old instance has time to quit, and opens the bundle
///   anew - the app has to quit itself afterwards.
public enum AppRestart {
    public enum Plan: Equatable, Sendable {
        case launchd(label: String)
        case relaunch(bundlePath: String)
    }

    /// The label of our own launchd agent that started this process. The same
    /// rule as with the autostart: "application.…" is what LaunchServices sets
    /// on every opening out of the Finder, the Dock or `open`, and that is no
    /// label kickstart can use.
    public static func launchdLabel(environment: [String: String]) -> String? {
        OnboardingAutostart.launchdLabel(environment: environment)
    }

    public static func plan(environment: [String: String], bundlePath: String) -> Plan {
        if let label = launchdLabel(environment: environment) { return .launchd(label: label) }
        return .relaunch(bundlePath: bundlePath)
    }

    /// The arguments for `/usr/bin/launchctl`.
    public static func launchctlArguments(label: String, uid: Int32) -> [String] {
        ["kickstart", "-k", "gui/\(uid)/\(label)"]
    }

    /// The command for `/bin/sh -c`: wait briefly, then open the bundle anew.
    /// `--relaunch` makes the new instance wait for the end of the old one
    /// instead of making room for it as a second instance (`SingleInstance`).
    public static func relaunchCommand(bundlePath: String) -> String {
        "sleep 1; open -n \"\(bundlePath)\" --args \(SingleInstance.relaunchArgument)"
    }
}
