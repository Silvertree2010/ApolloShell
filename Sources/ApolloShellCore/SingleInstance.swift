import Foundation

/// Nur eine ApolloShell gleichzeitig. Zwei Instanzen hiessen zwei Leisten,
/// doppelte Tastenkuerzel und zwei Besitzer von Apples Dock-Einstellung.
///
/// Eine zweite Instanz (Finder, Launchpad, Anmeldeobjekt neben dem
/// launchd-Agent) bittet die laufende per verteilter Mitteilung, Nexus zu
/// zeigen, und endet, bevor sie etwas anfasst.
///
/// Ausnahme: Eine Instanz, die eine andere ersetzt, startet, waehrend die alte
/// noch endet. Das sind der Neustart nach einem Sprachwechsel
/// (`relaunchArgument`) und `launchctl kickstart -k` eines launchd-Agents.
/// Sie wartet deshalb bis `replaceWait`, bevor sie aufgibt.
public enum SingleInstance {
    /// Startargument des Neustarts nach einem Sprachwechsel (`AppRestart`).
    public static let relaunchArgument = "--relaunch"

    /// So lange wartet eine ersetzende Instanz auf das Ende der alten. Die
    /// alte kann beim Beenden auf eine Administrator-Frage warten (Wach
    /// halten, zugeklappt) - gibt die neue vorher auf, laeuft danach keine.
    public static let replaceWait: TimeInterval = 60

    /// Verteilte Mitteilung an die laufende Instanz: "zeig dich".
    public static let showNotification = AppIdentity.scoped("show")
    public static let settingsNotification = AppIdentity.scoped("settings")
    public static let settingsArgument = "--settings"

    public static func settingsTarget(arguments: [String]) -> String?? {
        guard let i = arguments.firstIndex(of: settingsArgument) else { return nil }
        let n = arguments.index(after: i)
        guard n < arguments.endIndex, !arguments[n].hasPrefix("-") else { return .some(nil) }
        return .some(arguments[n])
    }

    public enum Decision: Equatable, Sendable {
        /// Keine andere Instanz: normal starten.
        case run
        /// Eine andere endet vermutlich gerade: nochmals nachsehen.
        case wait
        /// Die andere bleibt: ihr Nexus zeigen lassen und selbst enden.
        case handOver
    }

    public static func decide(otherInstances: Int, replacesOld: Bool, waitedLongEnough: Bool) -> Decision {
        if otherInstances == 0 { return .run }
        if replacesOld && !waitedLongEnough { return .wait }
        return .handOver
    }

    /// Ersetzt diese Instanz eine alte? Ja beim Sprachwechsel-Neustart und
    /// wenn ein eigener launchd-Agent sie gestartet hat.
    public static func replacesOld(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains(relaunchArgument) || OnboardingAutostart.launchdLabel(environment: environment) != nil
    }
}
