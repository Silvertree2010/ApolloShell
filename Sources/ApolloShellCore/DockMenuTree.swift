import Foundation

/// Ein Menueeintrag, so wie ihn die Bedienungshilfen melden - roh, ohne
/// Deutung.
///
/// Die Oberflaechen-Schicht liest diese Angaben aus Apples Dock; was daraus
/// wird, entscheidet `DockMenuTree` hier im Kern, damit es geprueft werden
/// kann, ohne ein Menue zu oeffnen.
public struct RawMenuItem: Equatable, Sendable {
    public let title: String
    public let enabled: Bool
    /// Das Zeichen, mit dem der Eintrag markiert ist (Apple setzt einen Haken
    /// an das vorderste Fenster); leer, wenn er unmarkiert ist.
    public let mark: String
    public let hasSubmenu: Bool
    public let children: [RawMenuItem]

    public init(title: String, enabled: Bool = true, mark: String = "",
                hasSubmenu: Bool = false, children: [RawMenuItem] = []) {
        self.title = title
        self.enabled = enabled
        self.mark = mark
        self.hasSubmenu = hasSubmenu
        self.children = children
    }
}

/// Eine Stufe auf dem Weg zu einem Menueeintrag: der Titel und die Stelle,
/// an der er in seinem Menue steht.
///
/// Die Stelle gehoert dazu, weil Titel sich wiederholen: zwei Fenster
/// desselben Dokuments, zwei zuletzt benutzte Dateien gleichen Namens. Nur
/// nach dem Titel zu suchen wuerde dann den falschen Eintrag druecken.
public struct DockMenuStep: Equatable, Sendable {
    public let title: String
    public let index: Int

    public init(title: String, index: Int) {
        self.title = title
        self.index = index
    }
}

/// Ein fertiger Eintrag fuer unser Menue.
public struct DockMenuNode: Equatable, Sendable {
    public let title: String
    public let enabled: Bool
    /// Mit Haken anzeigen.
    public let checked: Bool
    public let separator: Bool
    /// Der Weg ueber die Titel bis hierher. Damit wird der Eintrag in Apples
    /// Menue wiedergefunden, wenn es zum Ausfuehren noch einmal geoeffnet
    /// wird - die Elemente selbst gelten nur, solange es offen ist.
    public let path: [DockMenuStep]
    public let children: [DockMenuNode]

    public init(title: String, enabled: Bool, checked: Bool, separator: Bool,
                path: [DockMenuStep], children: [DockMenuNode]) {
        self.title = title
        self.enabled = enabled
        self.checked = checked
        self.separator = separator
        self.path = path
        self.children = children
    }
}

/// Macht aus dem, was in Apples Dock-Menue steht, unseren Menuebaum.
public enum DockMenuTree {
    /// Tiefer wird nicht gelesen. Apples Dock-Menue hat eine Ebene
    /// Untermenue ("Optionen"); alles darunter waere fremdes Gelaende.
    public static let maximumDepth = 2

    public static func nodes(from items: [RawMenuItem], path: [DockMenuStep] = [], depth: Int = 0) -> [DockMenuNode] {
        guard depth < maximumDepth else { return [] }
        return items.enumerated().map { index, item in
            // Apple meldet Trenner als Eintrag ohne Titel und ohne Untermenue.
            let separator = item.title.trimmingCharacters(in: .whitespaces).isEmpty && !item.hasSubmenu
            let ownPath = path + [DockMenuStep(title: item.title, index: index)]
            return DockMenuNode(
                title: item.title,
                enabled: item.enabled,
                checked: !item.mark.isEmpty,
                separator: separator,
                path: ownPath,
                children: item.hasSubmenu ? nodes(from: item.children, path: ownPath, depth: depth + 1) : []
            )
        }
    }

    /// Der Eintrag, der in Apples Dock anheftet - in den Sprachen, die die
    /// Shell selbst spricht.
    ///
    /// Warum er eine Sonderrolle hat: Er wuerde in **Apples** Dock anheften,
    /// das ausgeblendet ist, solange die Shell laeuft. Unser Menue haengt ihn
    /// deshalb an unser eigenes Dock. Trifft keiner der Namen zu, bleibt
    /// Apples Verhalten - lieber ein Eintrag, der etwas anderes tut als
    /// gedacht, als ein Menue, in dem er fehlt.
    public static func isKeepInDock(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed == "im dock behalten" || trimmed == "keep in dock"
    }
}
