import CoreGraphics

/// Geometrie fuer die Fensterwache: fremde Fenster sollen nicht unter die
/// linke Leiste laufen, so wie sie auch nicht unter den Dock laufen.
///
/// macOS kennt keine Schnittstelle, um Bildschirmplatz zu reservieren (der
/// `visibleFrame` gehoert allein Dock und Menueleiste). Die App schiebt
/// Fenster deshalb nachtraeglich per Bedienungshilfen zur Seite; hier steht
/// nur die reine Rechnung, damit sie ohne Fenster testbar ist.
///
/// Alle Rechtecke in EINEM Koordinatensystem. Die App rechnet in
/// Bedienungshilfen-Koordinaten (Ursprung oben links am Hauptbildschirm, y
/// nach unten), weil Fensterposition und -groesse dort so ankommen. Fuer das
/// Zurechtruecken selbst spielt die Richtung von y keine Rolle: es aendert
/// nur x und Breite.
public enum WindowClamp {
    /// Bruchteile eines Punkts ignorieren: Apps runden Positionen gern auf
    /// ganze Punkte, sonst wuerde ein Fenster bei x = 43.5 ewig nachgeschoben.
    public static let tolerance: CGFloat = 0.5

    /// Neuer Rahmen fuer ein Fenster, das in den reservierten Streifen am
    /// linken Rand von `screen` ragt, oder `nil`, wenn nichts zu tun ist.
    ///
    /// Zwei Faelle, weil sie verschieden entstanden sind:
    /// - Linke Kante genau am Bildschirmrand: das hat das System oder die App
    ///   so gelegt (Zoomen, "Fuellen", Kacheln links, Maximieren). Dann bleibt
    ///   die rechte Kante stehen und das Fenster wird schmaler - so wie diese
    ///   Befehle mit einem links angedockten Dock rechnen. Sonst wuerde eine
    ///   linke Kachel in die rechte hineingeschoben.
    /// - Sonst (von Hand halb daruntergezogen, links ueber den Rand
    ///   haengend): verschieben und die Groesse behalten. Nur wenn es dabei
    ///   rechts ueber den Bildschirm hinauslaufen wuerde, schmaler machen -
    ///   aber nie weiter nach rechts reichen lassen, als es schon reichte.
    ///
    /// `minWidth` ist die kleinste Breite, die die App zulaesst (gelernt aus
    /// einer abgelehnten Verkleinerung, sonst 0). Schmaler wird es nie; dann
    /// wird eben nur verschoben und das Fenster reicht weiter nach rechts.
    public static func clampedFrame(
        window: CGRect,
        screen: CGRect,
        reservedWidth: CGFloat,
        minWidth: CGFloat = 0
    ) -> CGRect? {
        guard reservedWidth > 0, window.width > 0, window.height > 0 else { return nil }
        let limit = screen.minX + reservedWidth
        guard window.minX < limit - tolerance else { return nil }

        var result = window
        result.origin.x = limit

        let pinnedWidth = window.maxX - limit
        if abs(window.minX - screen.minX) <= tolerance, pinnedWidth > 0 {
            result.size.width = max(pinnedWidth, minWidth)
        } else {
            let rightLimit = max(screen.maxX, window.maxX)
            result.size.width = max(min(window.width, rightLimit - limit), minWidth)
        }
        return result
    }

    /// Index des Bildschirms, auf dem der groesste Teil des Fensters liegt,
    /// oder `nil`, wenn es auf keinem liegt. Nur Fenster des Hauptbildschirms
    /// werden zurechtgerueckt; eines, das nur mit einem Zipfel von einem
    /// Bildschirm links daneben herueberragt, gehoert zu jenem.
    public static func dominantScreen(for window: CGRect, among screens: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = window.intersection(screen)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) {
                best = (index, area)
            }
        }
        return best?.index
    }

    /// AppKit (Ursprung unten links, y nach oben) <-> Bedienungshilfen
    /// (Ursprung oben links am Hauptbildschirm, y nach unten). Die Abbildung
    /// ist ihre eigene Umkehrung, deshalb eine Funktion fuer beide Richtungen.
    /// `primaryHeight` ist die Hoehe des Bildschirms mit der Menueleiste.
    public static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Gleich bis auf Rundung.
    public static func isSameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

/// Merkt sich pro Fenster, was die Wache zuletzt getan hat, damit sie sich
/// nicht mit einer App oder mit sich selbst in eine Schleife verbeisst.
///
/// - Echo: Das eigene Verschieben loest wieder "bewegt"-Meldungen aus. Steht
///   das Fenster noch genau dort, wo es nach dem letzten Eingriff stand, hat
///   es niemand bewegt - nichts tun. Gespeichert wird der danach GELESENE
///   Rahmen, nicht der gewuenschte: eine App, die nur halb nachgibt (z.B.
///   Mindestbreite), soll nicht immer wieder angestossen werden.
/// - Gegenwehr: Manche Apps legen ihr Fenster sofort zurueck. Mehr als
///   `maxAttempts` Eingriffe innerhalb von `period` Sekunden, dann Ruhe, bis
///   die Frist abgelaufen ist.
public struct ClampLedger<Key: Hashable> {
    public var maxAttempts: Int
    public var period: Double

    private var lastFrames: [Key: CGRect] = [:]
    private var attempts: [Key: [Double]] = [:]

    public init(maxAttempts: Int = 3, period: Double = 5) {
        self.maxAttempts = maxAttempts
        self.period = period
    }

    /// Darf das Fenster (mit diesem aktuellen Rahmen) jetzt angefasst werden?
    /// `now` in Sekunden auf einer beliebigen, monoton steigenden Uhr.
    public mutating func shouldClamp(_ key: Key, current: CGRect, now: Double) -> Bool {
        if let last = lastFrames[key], WindowClamp.isSameFrame(last, current) {
            return false
        }
        // Abgelaufene Versuche wegwerfen; leere Eintraege gar nicht erst
        // speichern, sonst waechst das Buch mit jedem je gesehenen Fenster.
        let recent = (attempts[key] ?? []).filter { now - $0 < period }
        attempts[key] = recent.isEmpty ? nil : recent
        return recent.count < maxAttempts
    }

    /// Nach einem Eingriff: den danach gelesenen Rahmen merken.
    public mutating func record(_ key: Key, result: CGRect, now: Double) {
        lastFrames[key] = result
        attempts[key, default: []].append(now)
    }

    /// Fenster geschlossen oder App beendet.
    public mutating func forget(_ key: Key) {
        lastFrames[key] = nil
        attempts[key] = nil
    }

    public mutating func forget(where predicate: (Key) -> Bool) {
        for key in lastFrames.keys where predicate(key) { lastFrames[key] = nil }
        for key in attempts.keys where predicate(key) { attempts[key] = nil }
    }

    /// Wie viele Fenster gerade gemerkt sind (fuer Tests und das Log).
    public var count: Int { Set(lastFrames.keys).union(attempts.keys).count }
}
