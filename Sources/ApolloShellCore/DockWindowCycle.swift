import Foundation

/// Klick auf die App, die schon vorne ist: ihr naechstes Fenster nach vorne,
/// wie ⌘`. Die Fensterliste kommt von vorne nach hinten
/// (Bedienungshilfen); das hinterste nach vorne holen laesst bei jedem Klick
/// ein anderes vorne stehen, bis alle einmal dran waren. Minimierte zaehlen
/// nicht - die holt man ueber das Menue.
public enum DockWindowCycle {
    /// Index des Fensters, das nach vorne soll; `nil` = nichts zu wechseln
    /// (App nicht vorne oder nur ein Fenster), dann gilt der normale Klick.
    public static func indexToRaise(isFrontmost: Bool, visibleWindows: Int) -> Int? {
        guard isFrontmost, visibleWindows > 1 else { return nil }
        return visibleWindows - 1
    }
}
