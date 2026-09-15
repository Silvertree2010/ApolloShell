import Foundation

/// Ob die Einfuehrung schon durch ist (settings.json, Abschnitt
/// "onboarding"). Frische Installationen: nein. Fehlt der Abschnitt in einer
/// vorhandenen Datei, war die Shell schon vor der Einfuehrung in Gebrauch -
/// dann gilt sie als erledigt und erscheint nicht von selbst.
public struct OnboardingSettings: Codable, Equatable, Sendable {
    public var completed: Bool

    public init(completed: Bool) {
        self.completed = completed
    }

    public static let firstLaunch = OnboardingSettings(completed: false)
    public static let existingInstall = OnboardingSettings(completed: true)

    /// Unlesbar heisst erledigt: ungefragt auftauchen stoert mehr, als dass
    /// sie fehlt - in Nexus > Über ist sie jederzeit zu haben.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completed = (try? c.decodeIfPresent(Bool.self, forKey: .completed)) ?? true
    }
}

/// Wann die Einfuehrung von selbst erscheint.
public enum OnboardingRule {
    /// Nur, solange sie nicht durch ist, und nicht im Nur-Launcher-Modus
    /// (dort gibt es weder Leiste noch Panels, die sie erklaert).
    public static func shouldShow(_ settings: ShellSettings, launcherOnly: Bool) -> Bool {
        !launcherOnly && !settings.onboarding.completed
    }
}

/// Die Schritte der Einfuehrung, in dieser Reihenfolge.
public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome, permissions, hotKeys, finish

    public var id: Self { self }

    /// Als `String`, nicht `LocalizedStringKey`: `Text(step.title)` in
    /// `Onboarding.swift` uebersetzt sonst nicht (String durch eine Variable
    /// - siehe Vertrag). `String(localized:)` schlaegt hier im Testprogramm
    /// (Bundle.main dort) auf denselben deutschen Text zurueck.
    public var title: String {
        switch self {
        case .welcome: String(localized: "Willkommen bei ApolloShell")
        case .permissions: String(localized: "Freigaben")
        case .hotKeys: String(localized: "Tastenkürzel")
        case .finish: String(localized: "Alles bereit")
        }
    }

    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    public var isLast: Bool { next == nil }

    /// Beschriftung des Hauptknopfs.
    public var primaryButton: String {
        switch self {
        case .welcome: String(localized: "Los geht’s")
        case .permissions, .hotKeys: String(localized: "Weiter")
        case .finish: String(localized: "Fertig")
        }
    }
}

/// Nur-Launcher-Modus (UserDefaults der App): nur der Launcher, keine
/// Leiste, Panels, Uhr oder Kurzmeldungen.
public enum LauncherOnlyFlag {
    public static let key = "launcherOnly"
    /// Fruehere Schreibweise, wird weiter gelesen.
    public static let legacyKey = "nurLauncher"

    /// `value`: liest einen Schluessel aus den UserDefaults (`object(forKey:)`).
    /// Der neue Schluessel gewinnt, sobald er gesetzt ist - auch als `false`.
    public static func isOn(_ value: (String) -> Any?) -> Bool {
        if let current = value(key) { return bool(current) }
        return value(legacyKey).map(bool) ?? false
    }

    /// Wie `UserDefaults.bool(forKey:)`: Zahlen und "YES"/"true" zaehlen.
    private static func bool(_ value: Any) -> Bool {
        switch value {
        case let flag as Bool: flag
        case let number as NSNumber: number.boolValue
        case let text as String: ["1", "yes", "true"].contains(text.lowercased())
        default: false
        }
    }
}

/// Bei der Anmeldung starten (SMAppService.mainApp) - was der Schalter
/// zeigt und ob er sich bedienen laesst.
public enum OnboardingAutostart {
    /// Spiegel von `SMAppService.Status`, damit die Regel ohne
    /// ServiceManagement testbar ist.
    public enum Status: Sendable {
        case notRegistered, enabled, requiresApproval, notFound
    }

    public struct State: Equatable, Sendable {
        public var isOn: Bool
        public var canToggle: Bool
        /// Wartet auf die Erlaubnis unter Allgemein > Anmeldeobjekte.
        public var needsApproval: Bool
        public var note: String?

        public init(isOn: Bool, canToggle: Bool, needsApproval: Bool = false, note: String? = nil) {
            self.isOn = isOn
            self.canToggle = canToggle
            self.needsApproval = needsApproval
            self.note = note
        }
    }

    /// Kennung des launchd-Auftrags, der diesen Prozess gestartet hat.
    /// launchd setzt XPC_SERVICE_NAME auf das Label des Auftrags; Apps, die
    /// LaunchServices oeffnet (Finder, Dock, `open`, Anmeldeobjekte), tragen
    /// "application.<bundle-id>.…", aus dem Terminal gestartete erben den Wert
    /// des Terminals (ebenfalls "application.…"). Gemessen 14.09., macOS 26.6.
    public static func launchdLabel(environment: [String: String]) -> String? {
        guard let name = environment["XPC_SERVICE_NAME"]?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty, name != "0", !name.hasPrefix("application.")
        else { return nil }
        return name
    }

    /// - Startet ein eigener launchd-Agent die Shell, bleibt der Schalter
    ///   aus und gesperrt: beides zusammen startete sie zweimal. Ist das
    ///   Anmeldeobjekt trotzdem an, laesst er sich ausschalten.
    /// - Ohne App-Bundle (Entwicklung, `swift run`) gesperrt: sonst stuende
    ///   ein Build-Ordner in den Anmeldeobjekten.
    public static func state(status: Status, launchdLabel: String?, isAppBundle: Bool) -> State {
        let on = status == .enabled || status == .requiresApproval
        if let launchdLabel {
            return State(isOn: on, canToggle: on, note: String(localized: "Startet schon über den launchd-Agenten „\(launchdLabel)“. Deshalb bleibt dieser Schalter aus – beides zusammen startete ApolloShell zweimal."))
        }
        guard isAppBundle else {
            return State(isOn: on, canToggle: on, note: String(localized: "Geht nur in der fertigen App (ApolloShell.app), nicht in einem Entwicklungs-Build."))
        }
        switch status {
        case .enabled:
            return State(isOn: true, canToggle: true)
        case .requiresApproval:
            return State(isOn: true, canToggle: true, needsApproval: true,
                         note: String(localized: "macOS wartet auf deine Erlaubnis unter Allgemein > Anmeldeobjekte."))
        case .notRegistered, .notFound:
            return State(isOn: false, canToggle: true)
        }
    }
}
