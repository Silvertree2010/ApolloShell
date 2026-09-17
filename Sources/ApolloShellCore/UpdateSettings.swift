import Foundation

/// Selbstaktualisierung (Nexus > Updates).
///
/// Die Vorgaben sind bewusst beide an: Wer die App laedt, soll die naechste
/// Fassung bekommen, ohne etwas zu tun. Sparkle fragt deshalb beim ersten
/// Start auch nicht nach - die Wahl steht stattdessen sichtbar in Nexus, und
/// README und Einfuehrung sagen es.
///
/// Eingespielt wird beim Beenden. Weil die Shell praktisch nie beendet wird,
/// zeigt Nexus zusaetzlich "Jetzt neu starten", sobald etwas bereitliegt.
///
/// Fuer eine Homebrew-Installation gelten beide Schalter nicht (siehe
/// `InstallKind`); dort wird nur gemeldet.
public struct UpdateSettings: Codable, Equatable, Sendable {
    /// Taeglich im Hintergrund nachsehen, ob es etwas Neues gibt.
    public var checkAutomatically: Bool
    /// Gefundene Updates ohne Rueckfrage laden und beim Beenden einspielen.
    public var installAutomatically: Bool
    /// Wann zuletzt nachgesehen wurde. Nur die Homebrew-Fassung schreibt das
    /// mit; bei der DMG-Fassung fuehrt Sparkle selbst Buch.
    public var lastCheck: Date?

    public init(checkAutomatically: Bool = true, installAutomatically: Bool = true, lastCheck: Date? = nil) {
        self.checkAutomatically = checkAutomatically
        self.installAutomatically = installAutomatically
        self.lastCheck = lastCheck
    }

    private enum CodingKeys: String, CodingKey {
        case checkAutomatically, installAutomatically, lastCheck
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkAutomatically = c.lenient(.checkAutomatically) ?? true
        installAutomatically = c.lenient(.installAutomatically) ?? true
        lastCheck = c.lenient(.lastCheck)
    }
}

/// Gewaehltes Theme (Nexus > Themes).
///
/// Gespeichert wird nur der Dateiname im Theme-Ordner ("Mitternacht.css"
/// oder "Mitternacht" als Ordner), nicht der ganze Pfad: So bleibt die
/// Einstellung gueltig, wenn der Ordner umzieht, und niemand kann ueber die
/// Datei auf einen Pfad ausserhalb des Theme-Ordners zeigen.
public struct ThemeSettings: Codable, Equatable, Sendable {
    /// Name im Theme-Ordner; `nil` = keins, die Shell sieht aus wie ohne Theme.
    public var name: String?

    public init(name: String? = nil) {
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case name
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let stored: String? = c.lenient(.name)
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Ein Pfadanteil waere ein Weg aus dem Ordner heraus; dann lieber keins.
        name = (trimmed.isEmpty || trimmed.contains("/") || trimmed.hasPrefix(".")) ? nil : trimmed
    }

    /// `name` auch ohne Wert als `null` schreiben, wie bei `providers`.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
    }
}

private extension KeyedDecodingContainer {
    /// Fehlt der Schluessel oder passt der Typ nicht: `nil` statt Fehler.
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
