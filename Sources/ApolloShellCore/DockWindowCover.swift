import Foundation

/// Ein Fenster auf dem Bildschirm, auf dem geklickt wurde - nur das Noetige
/// fuer die Verdeckt-Frage (`DockWindowCover`). `id` ist die Fensternummer
/// aus `CGWindowListCopyWindowInfo`, die Koordinaten deren Rechteck; welches
/// System (Cocoa oder Quartz) ist egal, solange alle Fenster im selben
/// Aufruf dasselbe benutzen - die Ueberlappung rechnet nur mit Abstaenden.
public struct DockScreenWindow: Equatable, Sendable {
    public enum Owner: Equatable, Sendable {
        /// Die App, auf deren Symbol geklickt wurde.
        case target
        /// Irgendeine andere App - kann ein Zielfenster verdecken.
        case other
        /// ApolloShells eigene Leisten/Panels: zaehlen nie als Verdecker,
        /// sonst wuerde die eigene Leiste am Bildschirmrand staendig als
        /// "verdeckt" durchgehen.
        case ownShell
    }

    public let id: Int
    public let owner: Owner
    /// Fensterebene aus `kCGWindowLayer`; nur Ebene 0 (normale Fenster) kann
    /// verdecken - Menueleiste, Dock, Status-Icons liegen hoeher und sind
    /// schmaler als jedes Fenster, wuerden also falsch als Verdecker zaehlen.
    public let layer: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(id: Int, owner: Owner, layer: Int, x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.owner = owner
        self.layer = layer
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var area: Double { width * height }
}

/// Welches Fenster der Zielapp auf dem aktuellen Bildschirm als naechstes
/// nach vorne soll, wenn man auf ihr schon vorne stehendes Symbol klickt -
/// wie bei Apple, nur blaettern, wenn wirklich etwas im Weg liegt. Liegen
/// mehrere Fenster frei nebeneinander, bleibt alles, wie es ist.
public enum DockWindowCover {
    /// Ab so viel verdeckter Flaeche zaehlt ein Fenster als "im Weg": ein
    /// Fenster, das nur am Rand ein paar Pixel unter einem anderen liegt
    /// (Schatten, knappes Nebeneinander), soll nicht bloss deshalb ganz nach
    /// vorne springen - man sieht es ja noch vollstaendig genug, um
    /// weiterzuarbeiten. Erst ab einem nennenswerten Teil der Flaeche stoert
    /// es wirklich. 10 % ist grosszuegig genug, um Zufalls-Ueberlappungen
    /// beim knappen Andocken zweier Fenster zu ignorieren, aber klein genug,
    /// um ein spuerbar verdecktes Fenster zu erkennen.
    public static let coverThreshold = 0.1

    /// `windows` von vorne nach hinten sortiert (wie `CGWindowListCopyWindowInfo`
    /// mit `.optionOnScreenOnly` liefert), schon auf den einen Bildschirm
    /// eingegrenzt. Liefert die `id` des vordersten verdeckten Fensters der
    /// Zielapp (das naechste, das ein Klick nach vorne holen soll), `nil`
    /// wenn keins verdeckt ist - auch wenn es nur ein einziges Fenster gibt
    /// oder alle frei nebeneinander liegen.
    public static func nextCovered(in windows: [DockScreenWindow]) -> Int? {
        for (index, window) in windows.enumerated() where window.owner == .target {
            let inFront = windows[..<index].filter { $0.owner == .other && $0.layer == 0 }
            if inFront.contains(where: { overlapFraction(of: window, coveredBy: $0) > coverThreshold }) {
                return window.id
            }
        }
        return nil
    }

    /// Anteil der Flaeche von `window`, den `other` verdeckt (0 bis 1).
    static func overlapFraction(of window: DockScreenWindow, coveredBy other: DockScreenWindow) -> Double {
        guard window.area > 0 else { return 0 }
        let x = max(window.x, other.x)
        let y = max(window.y, other.y)
        let width = min(window.x + window.width, other.x + other.width) - x
        let height = min(window.y + window.height, other.y + other.height) - y
        guard width > 0, height > 0 else { return 0 }
        return (width * height) / window.area
    }
}
