import CoreGraphics
import Foundation

/// Ein Bildschirm, so wie ihn die Auswahl sieht: Name, Rahmen, und ob er der
/// Hauptbildschirm ist (der mit der Menueleiste).
///
/// Bewusst ohne AppKit: die ganze Auswahl ist reine Rechnung und laesst sich
/// damit ohne Fenster und ohne angestecktes Kabel pruefen. Die App baut die
/// Liste aus `NSScreen.screens`.
public struct ScreenInfo: Equatable, Sendable, Identifiable {
    public var name: String
    /// Ganzer Rahmen in AppKit-Koordinaten (Ursprung unten links am
    /// Hauptbildschirm, y nach oben).
    public var frame: CGRect
    /// Der Bildschirm mit der Menueleiste. In `NSScreen.screens` ist das der
    /// erste; bei mehreren gilt trotzdem nur einer als Hauptbildschirm.
    public var isPrimary: Bool

    public init(name: String, frame: CGRect, isPrimary: Bool) {
        self.name = name
        self.frame = frame
        self.isPrimary = isPrimary
    }

    /// Stabiler Schluessel, unter dem eine Einstellung sich einen einzelnen
    /// Bildschirm merkt: Name plus Aufloesung.
    ///
    /// Warum nicht die Display-ID: die vergibt macOS beim Anstecken neu, ein
    /// gemerkter Bildschirm waere nach jedem Umstecken ein anderer. Name und
    /// Aufloesung ueberleben das.
    ///
    /// Preis: zwei baugleiche Bildschirme mit derselben Aufloesung haben
    /// denselben Schluessel und sind fuer die Einstellung nicht zu
    /// unterscheiden - dann gilt der erste (siehe `ScreenSelection.targets`).
    public var key: String { ScreenInfo.key(name: name, frame: frame) }

    public var id: String { key }

    /// Auf ganze Punkte gerundet: eine Aufloesung mit Nachkommastellen
    /// (skalierte Modi) ergaebe sonst bei jedem Aufwachen einen anderen
    /// Schluessel.
    public static func key(name: String, frame: CGRect) -> String {
        "\(name) \(Int(frame.width.rounded()))x\(Int(frame.height.rounded()))"
    }
}

/// Auf welchen Bildschirmen die Leiste steht (Nexus > Leiste).
public enum ScreenChoice: Equatable, Hashable, Sendable {
    /// Auf jedem angeschlossenen Bildschirm. Vorgabe.
    case all
    /// Nur auf dem Bildschirm mit der Menueleiste.
    case primary
    /// Nur auf einem bestimmten, gemerkt ueber `ScreenInfo.key`. Ist er nicht
    /// da, faellt es auf den Hauptbildschirm zurueck.
    case single(String)
}

extension ScreenChoice: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, screen
    }

    private enum Mode: String, Codable {
        case all, primary, single
    }

    private var mode: Mode {
        switch self {
        case .all: .all
        case .primary: .primary
        case .single: .single
        }
    }

    /// Nur bei `.single` ein Schluessel, sonst `null` - so steht er in der
    /// Datei und wer sie von Hand bearbeitet, findet ihn.
    private var screenKey: String? {
        switch self {
        case .single(let key): key
        case .all, .primary: nil
        }
    }

    /// Nachsichtig wie der Rest von settings.json: unbekannte oder fehlende
    /// Angaben ergeben die Vorgabe. `single` ohne brauchbaren Schluessel ist
    /// keine Auswahl, sondern eine kaputte Zeile - also ebenfalls die Vorgabe.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? nil
        let key = (((try? c.decodeIfPresent(String.self, forKey: .screen)) ?? nil))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .primary:
            self = .primary
        case .single:
            guard let key, !key.isEmpty else {
                self = .all
                return
            }
            self = .single(key)
        case .all, nil:
            self = .all
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(screenKey, forKey: .screen)
    }
}

/// Welche Bildschirme etwas bekommen und welcher unter dem Zeiger liegt.
///
/// Die ganze Bildschirm-Entscheidung der Shell steht hier, damit sie ohne
/// Fenster pruefbar ist: die App baut nur noch Fenster an die Rahmen, die
/// hier herauskommen.
public enum ScreenSelection {
    /// Die Bildschirme, auf denen die Leiste stehen soll.
    ///
    /// Leere Liste (Kabel mitten im Umstecken, alle Bildschirme schlafen):
    /// leeres Ergebnis. Die App laesst dann stehen, was steht, statt alles
    /// abzureissen und gleich wieder aufzubauen.
    public static func targets(among screens: [ScreenInfo], choice: ScreenChoice) -> [ScreenInfo] {
        guard !screens.isEmpty else { return [] }
        switch choice {
        case .all:
            return screens
        case .primary:
            return primary(among: screens).map { [$0] } ?? []
        case .single(let key):
            // Bei zwei baugleichen Bildschirmen (gleicher Schluessel) der
            // erste - "ein einzelner Bildschirm" soll einer bleiben.
            if let hit = screens.first(where: { $0.key == key }) { return [hit] }
            // Gemerkter Bildschirm ist nicht da: Hauptbildschirm.
            return primary(among: screens).map { [$0] } ?? []
        }
    }

    /// Der Bildschirm mit der Menueleiste; ohne Kennzeichnung der erste.
    public static func primary(among screens: [ScreenInfo]) -> ScreenInfo? {
        screens.first { $0.isPrimary } ?? screens.first
    }

    /// Der Bildschirm unter dem Zeiger.
    ///
    /// Genau auf der Kante zwischen zwei Bildschirmen gewinnt der, dessen
    /// Rahmen den Punkt enthaelt: `CGRect.contains` zaehlt die linke und
    /// untere Kante dazu, die rechte und obere nicht. Zwei Bildschirme
    /// nebeneinander teilen sich also keinen Punkt, und die Antwort ist
    /// eindeutig statt von der Reihenfolge abhaengig.
    ///
    /// Liegt der Punkt auf keinem Bildschirm (ganz oben an der Kante, oder in
    /// einer Luecke zwischen versetzt angeordneten Bildschirmen), gilt der
    /// naechstgelegene - der Zeiger ist ja sichtbar irgendwo.
    public static func screen(at point: CGPoint, among screens: [ScreenInfo]) -> ScreenInfo? {
        guard !screens.isEmpty else { return nil }
        if let hit = screens.first(where: { $0.frame.contains(point) }) { return hit }
        return screens.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    /// Quadratischer Abstand vom Punkt zum naechsten Punkt des Rahmens (0,
    /// wenn er darin liegt). Quadratisch genuegt fuer den Vergleich und
    /// spart die Wurzel.
    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
