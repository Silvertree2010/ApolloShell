import Foundation

/// Die drei Schluessel in `com.apple.dock`, die Apples eigenes Dock
/// vollstaendig verschwinden lassen (autohide, dazu die Verzoegerung vor
/// dem Einblenden am Bildschirmrand und die Animationsdauer auf null - sonst
/// blitzt es beim Hinfahren kurz auf).
///
/// Rein: liest und schreibt nichts selbst (kein `CFPreferences`, kein
/// `killall`) - das macht der App-Controller. Hier stehen nur die Werte und
/// die Entscheidungen, was wohin geschrieben gehoert.
public enum AppleDockHiding {
    public static let domain = "com.apple.dock"
    public static let autohideKey = "autohide"
    public static let autohideDelayKey = "autohide-delay"
    public static let autohideTimeModifierKey = "autohide-time-modifier"

    /// Ab dieser Verzoegerung (Sekunden) sieht ein gelesener Ist-Zustand
    /// schon versteckt aus - macOS' eigene Werte liegen weit darunter
    /// (Vorgabe 0,5 s). Schutz gegen doppeltes Sichern: startet ApolloShell,
    /// waehrend eine fruehere Version (oder das alte nix-config-Skript) das
    /// Verstecken schon dauerhaft gesetzt hatte, oder nach einem Absturz
    /// mitten im Versteckt-Zustand, gilt das NICHT als Original.
    public static let alreadyHiddenDelayThreshold: Double = 100

    public static let hidden = AppleDockPreferenceValues(
        autohide: true, autohideDelay: 1000, autohideTimeModifier: 0
    )

    /// Was aus dem gelesenen Ist-Zustand als Original gesichert wird.
    /// Sieht er schon versteckt aus (siehe `alreadyHiddenDelayThreshold`),
    /// gilt er nicht als Original - dann zaehlt die macOS-Vorgabe: alle drei
    /// Schluessel fehlen.
    public static func originalToSave(current: AppleDockPreferenceValues) -> AppleDockPreferenceValues {
        if let delay = current.autohideDelay, delay >= alreadyHiddenDelayThreshold {
            return AppleDockPreferenceValues()
        }
        return current
    }

    /// Was am Ende in `com.apple.dock` fuer `target` zu tun ist: Werte
    /// setzen, fehlende Schluessel loeschen (nicht auf einen macOS-Default
    /// zurueckschreiben, der sich einmal aendern koennte).
    public static func actions(toReach target: AppleDockPreferenceValues) -> [AppleDockPreferenceAction] {
        [
            target.autohide.map { AppleDockPreferenceAction.setBool(key: autohideKey, value: $0) }
                ?? .remove(key: autohideKey),
            target.autohideDelay.map { AppleDockPreferenceAction.setDouble(key: autohideDelayKey, value: $0) }
                ?? .remove(key: autohideDelayKey),
            target.autohideTimeModifier.map { AppleDockPreferenceAction.setDouble(key: autohideTimeModifierKey, value: $0) }
                ?? .remove(key: autohideTimeModifierKey),
        ]
    }
}

/// Eine Aenderung an genau einem Schluessel in `com.apple.dock`.
public enum AppleDockPreferenceAction: Equatable, Sendable {
    case setBool(key: String, value: Bool)
    case setDouble(key: String, value: Double)
    case remove(key: String)
}

/// Die drei Schluessel, jeder ein Wert oder "fehlt" (`nil`) - fehlt einer,
/// stand er nicht in `com.apple.dock`.
public struct AppleDockPreferenceValues: Codable, Equatable, Sendable {
    public var autohide: Bool?
    public var autohideDelay: Double?
    public var autohideTimeModifier: Double?

    public init(autohide: Bool? = nil, autohideDelay: Double? = nil, autohideTimeModifier: Double? = nil) {
        self.autohide = autohide
        self.autohideDelay = autohideDelay
        self.autohideTimeModifier = autohideTimeModifier
    }

    /// Inhalt von apple-dock.json (das gesicherte Original). Fehlt die
    /// Datei: `nil` - kein Original gesichert, also lief ApolloShell noch
    /// nicht mit aktivem Verstecken oder hat sauber aufgeraeumt.
    public static func load(from data: Data?) -> AppleDockPreferenceValues? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AppleDockPreferenceValues.self, from: data)
    }

    /// Sortierte Schluessel und eingerueckt, wie die uebrigen Dateien der
    /// Shell - von Hand lesbar.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
