import CoreGraphics

/// Wann ein Kantenfenster per Maus erscheint und wieder geht - Regeln aus
/// Caelestia (modules/drawers/Interactions.qml):
/// - Maus im Bereich: sichtbar, Maus raus: weg.
/// - Per Tastenkombination oder Symbol geoeffnet ("Shortcut-Modus"): bleibt
///   offen, egal wo die Maus ist - bis sie einmal hineinfaehrt; ab dann gilt
///   wieder die Maus-Regel.
public struct EdgeHoverState: Equatable, Sendable {
    public var visible: Bool
    public var shortcutActive: Bool

    public init(visible: Bool, shortcutActive: Bool) {
        self.visible = visible
        self.shortcutActive = shortcutActive
    }

    public static let hidden = EdgeHoverState(visible: false, shortcutActive: false)

    public func moved(inArea: Bool) -> EdgeHoverState {
        if !shortcutActive { return EdgeHoverState(visible: inArea, shortcutActive: false) }
        if inArea { return EdgeHoverState(visible: visible, shortcutActive: false) }
        return self
    }

    /// Caelestia: liegt die Maus beim Oeffnen schon im Bereich, gilt gleich
    /// die Maus-Regel.
    public static func openedByShortcut(mouseInArea: Bool) -> EdgeHoverState {
        EdgeHoverState(visible: true, shortcutActive: !mouseInArea)
    }
}

/// Der Bereich, in dem die Maus ein Kantenfenster oeffnet bzw. offen haelt
/// (AppKit-Koordinaten, y nach oben).
public enum EdgeHoverArea {
    /// Caelestia: border.minThickness - so dick ist der Ausloese-Streifen an
    /// der Kante, solange das Fenster zu ist.
    public static let edgeThickness: CGFloat = 2

    /// Oben mittig. Zu: nur der Streifen an der Oberkante, so breit wie das
    /// Fenster plus Rundung. Offen: das ganze Fenster (`depth` ab der
    /// Oberkante). Ragt etwas ueber den Rand, damit die oberste Pixelzeile
    /// sicher dazugehoert.
    public static func top(screen: CGRect, width: CGFloat, depth: CGFloat, margin: CGFloat, open: Bool) -> CGRect {
        let reach = open ? depth : edgeThickness
        return CGRect(
            x: screen.midX - width / 2 - margin,
            y: screen.maxY - reach,
            width: width + 2 * margin,
            height: reach + edgeThickness
        )
    }

    /// Die heisse Ecke unten rechts belegt macOS von Haus aus mit der
    /// Schnellnotiz. Die letzten
    /// Punkte vor der Ecke loesen deshalb nichts aus: faehrt man ganz in die
    /// Ecke, kommt die Schnellnotiz, knapp daneben am Rand das Panel.
    public static let cornerGap: CGFloat = 12

    /// Unten rechts (Utilities). Zu: Streifen am unteren Rand, von der
    /// linken Panelkante (minus Rundung) bis kurz vor die Ecke. Offen: das
    /// ganze Panel bis an den rechten Rand.
    public static func bottomRight(screen: CGRect, width: CGFloat, height: CGFloat, margin: CGFloat, open: Bool) -> CGRect {
        let left = screen.maxX - width - margin
        let right = open ? screen.maxX + edgeThickness : screen.maxX - cornerGap
        let reach = open ? height : edgeThickness
        return CGRect(x: left, y: screen.minY - edgeThickness, width: right - left, height: reach + edgeThickness)
    }
}

/// Was `EdgeDrawer.close(then:)` mit seiner Aktion tut. Das Panel bleibt
/// klickbar, solange es ausblendet: Ein zweiter Klick in dieser Zeit (ein
/// Doppelklick auf Bildschirmfoto) darf die Aktion weder sofort noch ein
/// zweites Mal ausloesen.
public enum DrawerCloseStep: Equatable, Sendable {
    /// Offen: schliessen, die Aktion nach dem Ausblenden.
    case closeThenRun
    /// Blendet gerade aus, noch nichts vorgemerkt: nach dem Ausblenden.
    case runAfterFade
    /// Blendet aus, eine Aktion ist schon vorgemerkt: die erste gilt.
    case drop
    /// Ganz weg: sofort.
    case runNow

    public init(isOpen: Bool, isVisible: Bool, hasPendingAction: Bool) {
        if isOpen {
            self = .closeThenRun
        } else if isVisible {
            self = hasPendingAction ? .drop : .runAfterFade
        } else {
            self = .runNow
        }
    }
}
