import Foundation

/// "Wach halten" auch bei zugeklapptem Deckel.
///
/// Die Energie-Zusicherung haelt den Mac nur bei Untaetigkeit wach;
/// Zuklappen schickt ihn trotzdem schlafen. Das verhindert nur
/// `pmset -a disablesleep 1`, und das braucht root. So macht es auch
/// Amphetamine ("Closed-Display Mode").
///
/// Zuerst `sudo -n` (ohne Rueckfrage, klappt nur mit passwortlosem sudo).
/// Sonst fragt macOS ueber AppleScript nach einem Administrator - beim
/// Einschalten und beim Zuruecksetzen. Wer ablehnt, bekommt "Wach halten"
/// ohne den Deckel-Teil.
public enum LidAwake {
    /// Im Akkubetrieb endet "Wach halten" ab dieser Ladung von selbst: ein
    /// zugeklappter Mac in der Tasche soll nicht leerlaufen oder heiss werden.
    public static let batteryFloor = 10

    public static let pmset = "/usr/bin/pmset"
    public static let sudo = "/usr/bin/sudo"
    public static let osascript = "/usr/bin/osascript"

    /// Wert von "SleepDisabled" aus `pmset -g`; `nil`, wenn die Zeile fehlt.
    public static func sleepDisabled(pmsetOutput: String) -> Bool? {
        for line in pmsetOutput.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2, parts[0] == "SleepDisabled" { return parts[1] == "1" }
        }
        return nil
    }

    public static func shouldStop(battery: BatteryState?) -> Bool {
        guard let battery, !battery.onAC else { return false }
        return battery.level <= batteryFloor
    }

    /// `sudo -n pmset -a disablesleep 1|0`: ohne Passwort oder gar nicht,
    /// wartet nie auf eine Eingabe.
    public static func sudoArguments(disableSleep: Bool) -> [String] {
        ["-n", pmset, "-a", "disablesleep", disableSleep ? "1" : "0"]
    }

    /// Dasselbe mit Administrator-Rueckfrage von macOS. Der Text sagt, wozu -
    /// ein nackter Passwort-Dialog ohne Grund waere verdaechtig.
    public static func adminScript(disableSleep: Bool) -> String {
        // Wird in macOS' eigenem Passwort-Dialog gezeigt (osascript "with
        // prompt") - kein SwiftUI-Text, deshalb hier schon uebersetzt.
        let prompt = disableSleep
            ? String(localized: "ApolloShell möchte den Ruhezustand bei zugeklapptem Deckel aussetzen, solange „Wach halten“ läuft.")
            : String(localized: "ApolloShell möchte den Ruhezustand bei zugeklapptem Deckel wieder erlauben.")
        return "do shell script \"\(pmset) -a disablesleep \(disableSleep ? "1" : "0")\" "
            + "with prompt \"\(prompt)\" with administrator privileges"
    }

    public static func osascriptArguments(disableSleep: Bool) -> [String] {
        ["-e", adminScript(disableSleep: disableSleep)]
    }
}

/// Einstellung zu "Wach halten" (settings.json, Abschnitt "keepAwake").
///
/// `lidClosed`: auch zugeklappt. Frische Installationen: aus - es braucht
/// Administratorrechte und laesst einen Mac in der Tasche wach. Fehlt der
/// Abschnitt in einer vorhandenen Datei: an, denn davor galt es immer.
public struct KeepAwakeSettings: Codable, Equatable, Sendable {
    public var lidClosed: Bool

    public init(lidClosed: Bool) {
        self.lidClosed = lidClosed
    }

    public static let firstLaunch = KeepAwakeSettings(lidClosed: false)
    public static let existingInstall = KeepAwakeSettings(lidClosed: true)

    /// Abschnitt da, Schluessel fehlt oder unlesbar: aus (die sichere Seite).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lidClosed = (try? c.decodeIfPresent(Bool.self, forKey: .lidClosed)) ?? false
    }
}

/// Einstellung zu "Apple-Dock ausblenden, solange ApolloShell laeuft"
/// (settings.json, Abschnitt "appleDockHiding"). Gleiches Muster wie
/// `KeepAwakeSettings`: frische Installationen aus (bis jemand sich dafuer
/// entscheidet), vorhandene Dateien ohne diesen Abschnitt an (das erledigte
/// bisher das nix-config dauerhaft von aussen), Abschnitt ohne den
/// Schluessel aus (die sichere Seite).
public struct AppleDockHidingSettings: Codable, Equatable, Sendable {
    public var hideWhileRunning: Bool

    public init(hideWhileRunning: Bool) {
        self.hideWhileRunning = hideWhileRunning
    }

    public static let firstLaunch = AppleDockHidingSettings(hideWhileRunning: false)
    public static let existingInstall = AppleDockHidingSettings(hideWhileRunning: true)

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hideWhileRunning = (try? c.decodeIfPresent(Bool.self, forKey: .hideWhileRunning)) ?? false
    }
}

/// Wie es gerade um den Deckel-Teil von "Wach halten" steht.
public enum KeepAwakeLid: Equatable, Sendable {
    /// Nicht gewuenscht (Einstellung aus) oder Wach halten aus.
    case off
    /// Gilt auch zugeklappt.
    case on
    /// macOS fragt gerade nach einem Administrator.
    case pending
    /// Abgelehnt oder fehlgeschlagen: wach nur aufgeklappt.
    case declined
}
