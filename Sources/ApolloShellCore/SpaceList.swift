import Foundation

/// Die Spaces des Hauptbildschirms, so wie die Leiste sie zeigt.
public struct SpaceSnapshot: Equatable, Sendable {
    /// Kennungen der Schreibtische in Mission-Control-Reihenfolge.
    public var desktops: [UInt64]
    /// Stelle des aktiven Schreibtischs in `desktops`. `nil`, wenn gerade
    /// ein Vollbild-Space aktiv ist - dann ist die Leiste ohnehin weg
    /// (WindowGuard blendet sie aus).
    public var activeIndex: Int?

    public init(desktops: [UInt64], activeIndex: Int?) {
        self.desktops = desktops
        self.activeIndex = activeIndex
    }
}

/// Wertet die Space-Liste von SkyLight aus.
///
/// macOS hat fuer Spaces keine oeffentliche Schnittstelle. Die Daten kommen
/// aus `CGSCopyManagedDisplaySpaces` (privat, nur lesend, ohne Freigabe;
/// der Aufruf steht in SpacesModel.swift). Hier nur das Auswerten, damit es
/// ohne WindowServer testbar ist.
///
/// Form, gemessen am 14.09. auf macOS 26.6: pro Bildschirm ein Woerterbuch
/// mit "Display Identifier" (UUID des Bildschirms; "Main", wenn
/// "Bildschirme verwenden verschiedene Spaces" aus ist), "Spaces" und
/// "Current Space". Jeder Space hat "id64" und "ManagedSpaceID" (dieselbe
/// Zahl) und "type". Die Liste steht in Mission-Control-Reihenfolge, nicht
/// nach Kennung sortiert: gemessen kam Space 3 vor Space 1.
public enum SpaceList {
    /// Normaler Schreibtisch.
    public static let desktopType = 0
    /// Vollbild-App (auch Split View).
    public static let fullscreenType = 4
    /// Kennung, wenn sich alle Bildschirme die Spaces teilen.
    public static let sharedDisplayIdentifier = "Main"

    /// Vollbild-Spaces zeigt die Leiste nicht: Mission Control nummeriert
    /// nur die Schreibtische ("Schreibtisch 1...n"), Ctrl+Zahl springt nur
    /// zu ihnen, und in einem Vollbild-Space ist die Leiste ausgeblendet -
    /// ein Punkt dafuer koennte nie aktiv zu sehen sein.
    ///
    /// `nil`, wenn nichts Brauchbares darin steht; dann zeigt die Leiste
    /// keine Kapsel statt einer falschen.
    public static func snapshot(displays: [[String: Any]], mainDisplay: String?) -> SpaceSnapshot? {
        guard let display = pickDisplay(displays, mainDisplay: mainDisplay),
              let spaces = display["Spaces"] as? [[String: Any]]
        else { return nil }
        let desktops = spaces.compactMap { space -> UInt64? in
            // Ohne "type" nicht raten: lieber einen Punkt zu wenig.
            guard (space["type"] as? NSNumber)?.intValue == desktopType else { return nil }
            return spaceID(space)
        }
        guard !desktops.isEmpty else { return nil }
        let current = (display["Current Space"] as? [String: Any]).flatMap(spaceID)
        return SpaceSnapshot(
            desktops: desktops,
            activeIndex: current.flatMap { desktops.firstIndex(of: $0) }
        )
    }

    /// Kennungen (gross geschrieben) der Bildschirme, deren aktiver Space
    /// eine Vollbild-App zeigt. Dort tritt die Leiste ab.
    ///
    /// Gefragt wird der Space selbst, nicht die Vordergrund-App: ein
    /// Vollbild-Video auf dem einen Bildschirm bleibt Vollbild, auch wenn
    /// der Fokus auf einem Fenster des anderen liegt.
    ///
    /// `nil`, wenn kein Bildschirm lesbar ist; dann bleibt der alte Stand.
    /// "Main" steht fuer alle Bildschirme (gemeinsame Spaces).
    public static func fullscreenDisplays(_ displays: [[String: Any]]) -> Set<String>? {
        var result: Set<String> = []
        var readable = false
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any]
            else { continue }
            readable = true
            if spaceType(current, in: display) == fullscreenType {
                result.insert(identifier.uppercased())
            }
        }
        return readable ? result : nil
    }

    /// Typ des Space; fehlt er am Eintrag selbst, aus der Liste des
    /// Bildschirms nach Kennung.
    static func spaceType(_ space: [String: Any], in display: [String: Any]) -> Int? {
        if let type = (space["type"] as? NSNumber)?.intValue { return type }
        guard let id = spaceID(space),
              let spaces = display["Spaces"] as? [[String: Any]],
              let match = spaces.first(where: { spaceID($0) == id })
        else { return nil }
        return (match["type"] as? NSNumber)?.intValue
    }

    /// Der Bildschirm mit der Menueleiste (dort steht die Leiste): nach UUID,
    /// sonst der gemeinsame "Main", sonst der erste.
    static func pickDisplay(_ displays: [[String: Any]], mainDisplay: String?) -> [String: Any]? {
        func identifier(_ display: [String: Any]) -> String? { display["Display Identifier"] as? String }
        if let mainDisplay,
           let match = displays.first(where: { identifier($0)?.caseInsensitiveCompare(mainDisplay) == .orderedSame }) {
            return match
        }
        if let shared = displays.first(where: { identifier($0) == sharedDisplayIdentifier }) {
            return shared
        }
        return displays.first
    }

    static func spaceID(_ space: [String: Any]) -> UInt64? {
        ((space["id64"] ?? space["ManagedSpaceID"]) as? NSNumber)?.uint64Value
    }
}
