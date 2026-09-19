import Foundation

/// Neustart der App, damit eine neue Einstellung gilt.
///
/// Zwei Wege, je nachdem, wer den Prozess gestartet hat:
/// - Ein eigener launchd-Agent (macOS setzt dann `XPC_SERVICE_NAME` auf
///   dessen Label): `launchctl kickstart -k` startet ihn neu.
/// - Sonst (Finder, `open`, Entwicklungsbuild): ein Hilfsprozess wartet
///   kurz, damit die alte Instanz Zeit zum Beenden hat, und oeffnet das
///   Bundle neu - die App muss sich danach selbst beenden.
public enum AppRestart {
    public enum Plan: Equatable, Sendable {
        case launchd(label: String)
        case relaunch(bundlePath: String)
    }

    /// Label des eigenen launchd-Agents, der diesen Prozess gestartet hat.
    /// Dieselbe Regel wie beim Autostart: "application.…" setzt
    /// LaunchServices bei jedem Oeffnen aus Finder, Dock oder `open`, das ist
    /// kein kickstart-faehiges Label.
    public static func launchdLabel(environment: [String: String]) -> String? {
        OnboardingAutostart.launchdLabel(environment: environment)
    }

    public static func plan(environment: [String: String], bundlePath: String) -> Plan {
        if let label = launchdLabel(environment: environment) { return .launchd(label: label) }
        return .relaunch(bundlePath: bundlePath)
    }

    /// Argumente fuer `/usr/bin/launchctl`.
    public static func launchctlArguments(label: String, uid: Int32) -> [String] {
        ["kickstart", "-k", "gui/\(uid)/\(label)"]
    }

    /// Befehl fuer `/bin/sh -c`: kurz warten, dann das Bundle neu oeffnen.
    /// `--relaunch` laesst die neue Instanz auf das Ende der alten warten,
    /// statt ihr als zweite Instanz Platz zu machen (`SingleInstance`).
    public static func relaunchCommand(bundlePath: String) -> String {
        "sleep 1; open -n \"\(bundlePath)\" --args \(SingleInstance.relaunchArgument)"
    }
}
