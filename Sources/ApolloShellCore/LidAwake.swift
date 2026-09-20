import Foundation

/// "Keep Awake" auch bei zugeklapptem Deckel.
///
/// Die Energie-Zusicherung haelt den Mac nur bei Untaetigkeit wach;
/// Zuklappen schickt ihn trotzdem schlafen. Das verhindert nur
/// `pmset -a disablesleep 1`, und das braucht root. So macht es auch
/// Amphetamine ("Closed-Display Mode").
///
/// Zuerst `sudo -n` (ohne Rueckfrage, klappt nur mit passwortlosem sudo).
/// Sonst fragt macOS ueber AppleScript nach einem Administrator. Beim
/// ersten Einschalten richtet dieselbe Frage eine eng begrenzte sudo-Regel
/// ein (`sudoersRule`): danach geht beides ohne Passwort, auch das
/// Zuruecksetzen beim Beenden und beim Akku-Schutz, wenn niemand da ist,
/// der eine Frage beantworten koennte. Wer ablehnt, bekommt "Keep Awake"
/// ohne den Deckel-Teil.
public enum LidAwake {
    /// Im Akkubetrieb endet "Keep Awake" ab dieser Ladung von selbst: ein
    /// zugeklappter Mac in der Tasche soll nicht leerlaufen oder heiss werden.
    public static let batteryFloor = 10

    public static let pmset = "/usr/bin/pmset"
    public static let sudo = "/usr/bin/sudo"
    public static let osascript = "/usr/bin/osascript"
    static let visudo = "/usr/sbin/visudo"
    /// Die Regel, die ApolloShell einmalig anlegt. macOS liest den Ordner
    /// ueber `#includedir /private/etc/sudoers.d` in /etc/sudoers.
    public static let sudoersFile = "/etc/sudoers.d/apolloshell"

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
    ///
    /// `installRuleFor`: beim Einschalten zusaetzlich die Regel ohne Passwort
    /// fuer diesen Nutzer anlegen. Ein Name, der nicht sicher in eine
    /// sudoers-Zeile passt, laesst die Regel weg.
    public static func adminScript(disableSleep: Bool, installRuleFor user: String? = nil) -> String {
        var command = "\(pmset) -a disablesleep \(disableSleep ? "1" : "0")"
        let install = disableSleep ? user.flatMap(installRuleCommand(user:)) : nil
        if let install { command += " && { \(install); true; }" }
        // Wird in macOS' eigenem Passwort-Dialog gezeigt (osascript "with
        // prompt") - kein SwiftUI-Text, deshalb hier schon uebersetzt.
        let prompt: String
        if !disableSleep {
            prompt = String(localized: "ApolloShell would like to allow sleep with the lid closed again.")
        } else if install != nil {
            prompt = String(localized: "ApolloShell would like to suspend sleep with the lid closed while “Keep Awake” is on. So this works without a password from now on, it adds a rule that allows only this one command.")
        } else {
            prompt = String(localized: "ApolloShell would like to suspend sleep with the lid closed while “Keep Awake” is on.")
        }
        return shellScript(command, prompt: prompt)
    }

    public static func osascriptArguments(disableSleep: Bool, installRuleFor user: String? = nil) -> [String] {
        ["-e", adminScript(disableSleep: disableSleep, installRuleFor: user)]
    }

    /// Die Regel wieder entfernen (Nexus).
    public static func removeRuleArguments() -> [String] {
        let prompt = String(localized: "ApolloShell would like to remove its rule that switches lid-closed sleep without a password.")
        return ["-e", shellScript("/bin/rm -f \(sudoersFile)", prompt: prompt)]
    }

    // MARK: Regel ohne Passwort

    /// Nur gewoehnliche Kurznamen: der Name landet unverändert in einer
    /// sudoers-Zeile und in einem Shell-Befehl. Alles andere (Leerzeichen,
    /// Komma, Anfuehrungszeichen, `%gruppe`, Umlaute) laesst die Regel weg.
    static func isSafeUserName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first != "-" else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar))
        }
    }

    /// Erlaubt genau die zwei Aufrufe aus `sudoArguments`, nur als root und
    /// nur fuer diesen Nutzer. Keine Anfuehrungszeichen und kein Backslash:
    /// der Text steht in einfachen Anfuehrungszeichen der Shell und in einem
    /// AppleScript-String.
    public static func sudoersRule(user: String) -> String? {
        guard isSafeUserName(user) else { return nil }
        let allowed = [true, false]
            .map { sudoArguments(disableSleep: $0).dropFirst().joined(separator: " ") }
            .joined(separator: ", ")
        return """
        # Written by ApolloShell: lets Keep Awake switch lid sleep without a password.
        # Allows only the two commands below. Remove it in Nexus or with: sudo rm \(sudoersFile)
        \(user) ALL=(root) NOPASSWD: \(allowed)

        """
    }

    /// Laeuft als root: Regel in eine eigene Datei schreiben, mit visudo
    /// pruefen, Rechte setzen und erst dann an ihren Platz. Eine fehlerhafte
    /// Regel kommt so nie in den Ordner, den sudo liest.
    static func installRuleCommand(user: String) -> String? {
        guard let rule = sudoersRule(user: user) else { return nil }
        let lines = rule.split(separator: "\n").map { "'\($0)'" }.joined(separator: " ")
        return [
            "t=$(/usr/bin/mktemp /private/tmp/apolloshell-sudoers.XXXXXX)",
            "/usr/bin/printf '%s\\n' \(lines) > \"$t\"",
            "\(visudo) -cf \"$t\" >/dev/null",
            "/usr/sbin/chown root:wheel \"$t\"",
            "/bin/chmod 0440 \"$t\"",
            "/bin/mv -f \"$t\" \(sudoersFile)",
        ].joined(separator: " && ") + "; /bin/rm -f \"$t\""
    }

    /// `do shell script` mit Administrator-Frage; Befehl und Text als
    /// AppleScript-Strings maskiert.
    static func shellScript(_ command: String, prompt: String) -> String {
        "do shell script \"\(appleScriptEscaped(command))\" "
            + "with prompt \"\(appleScriptEscaped(prompt))\" with administrator privileges"
    }

    static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// Einstellung zu "Keep Awake" (settings.json, Abschnitt "keepAwake").
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

/// Wie es gerade um den Deckel-Teil von "Keep Awake" steht.
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
