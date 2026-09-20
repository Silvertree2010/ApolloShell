import CoreGraphics

/// When an edge window appears by mouse and goes again - the rules out of
/// Caelestia (modules/drawers/Interactions.qml):
/// - The mouse in the area: visible, the mouse out: away.
/// - Opened by a shortcut or a symbol ("shortcut mode"): it stays open,
///   wherever the mouse is - until it moves in once; from then on the mouse
///   rule holds again.
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

    /// Caelestia: when the mouse lies in the area at the opening, the mouse
    /// rule holds right away.
    public static func openedByShortcut(mouseInArea: Bool) -> EdgeHoverState {
        EdgeHoverState(visible: true, shortcutActive: !mouseInArea)
    }
}

/// The area in which the mouse opens an edge window or keeps it open (AppKit
/// coordinates, y upwards).
public enum EdgeHoverArea {
    /// Caelestia: border.minThickness - this is how thick the trigger strip at
    /// the edge is while the window is closed.
    public static let edgeThickness: CGFloat = 2

    /// Top centre. Closed: only the strip at the top edge, as wide as the
    /// window plus the corner. Open: the whole window (`depth` from the top
    /// edge). It sticks out over the edge a little, so that the topmost row of
    /// pixels surely belongs to it.
    public static func top(screen: CGRect, width: CGFloat, depth: CGFloat, margin: CGFloat, open: Bool) -> CGRect {
        let reach = open ? depth : edgeThickness
        return CGRect(
            x: screen.midX - width / 2 - margin,
            y: screen.maxY - reach,
            width: width + 2 * margin,
            height: reach + edgeThickness
        )
    }

    /// The hot corner at the bottom right is taken by macOS out of the box for
    /// the quick note. The last points before the corner therefore set nothing
    /// off: driving right into the corner brings the quick note, just beside it
    /// at the edge the panel.
    public static let cornerGap: CGFloat = 12

    /// Bottom right (utilities). Closed: a strip at the bottom edge, from the
    /// left panel edge (minus the corner) to just before the corner. Open: the
    /// whole panel up to the right edge.
    public static func bottomRight(screen: CGRect, width: CGFloat, height: CGFloat, margin: CGFloat, open: Bool) -> CGRect {
        let left = screen.maxX - width - margin
        let right = open ? screen.maxX + edgeThickness : screen.maxX - cornerGap
        let reach = open ? height : edgeThickness
        return CGRect(x: left, y: screen.minY - edgeThickness, width: right - left, height: reach + edgeThickness)
    }
}

/// What `EdgeDrawer.close(then:)` does with its action. The panel stays
/// clickable while it fades out: a second click in that time (a double click
/// on the screenshot) may set the action off neither right away nor a second
/// time.
public enum DrawerCloseStep: Equatable, Sendable {
    /// Open: close, and the action after the fade-out.
    case closeThenRun
    /// Fading out right now, nothing noted yet: after the fade-out.
    case runAfterFade
    /// Fading out, an action noted already: the first one holds.
    case drop
    /// Fully gone: right away.
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
