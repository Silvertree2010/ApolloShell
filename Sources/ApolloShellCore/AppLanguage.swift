import Foundation

/// Sprache der Oberflaeche (Nexus > Allgemein). Wirkt erst nach einem
/// Neustart von ApolloShell - SwiftUI und AppKit lesen `AppleLanguages` nur
/// beim Start.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, german, english

    public var id: Self { self }

    /// Schluessel in der UserDefaults-Domaene der App. Kein `AppleLanguages`
    /// in `Info.plist` und keine JSON-Einstellung - das ist AppKits eigener
    /// Mechanismus, gilt also nur fuer diese App.
    public static let defaultsKey = "AppleLanguages"

    /// Wert fuer `defaultsKey`, oder `nil` fuer "System" (Schluessel entfernen).
    public var appleLanguages: [String]? {
        switch self {
        case .system: nil
        case .german: ["de"]
        case .english: ["en"]
        }
    }

    /// Aus dem gespeicherten Wert von `defaultsKey` (z. B.
    /// `UserDefaults.standard.array(forKey:)`). Alles ausser "de" oder "en"
    /// vorn (leer, mehrsprachig, unbekannt) zaehlt als "System".
    public init(appleLanguages: [String]?) {
        switch appleLanguages?.first {
        case "de": self = .german
        case "en": self = .english
        default: self = .system
        }
    }
}

/// Neustart der App, damit eine neue Sprache gilt.
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
