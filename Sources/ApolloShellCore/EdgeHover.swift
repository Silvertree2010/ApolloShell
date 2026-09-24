import CoreGraphics

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

    public static func openedByShortcut(mouseInArea: Bool) -> EdgeHoverState {
        EdgeHoverState(visible: true, shortcutActive: !mouseInArea)
    }
}

public enum EdgeHoverArea {
    public static let edgeThickness: CGFloat = 2

    public static func top(screen: CGRect, width: CGFloat, depth: CGFloat, margin: CGFloat, open: Bool) -> CGRect {
        let reach = open ? depth : edgeThickness
        return CGRect(
            x: screen.midX - width / 2 - margin,
            y: screen.maxY - reach,
            width: width + 2 * margin,
            height: reach + edgeThickness
        )
    }

    public static let cornerGap: CGFloat = 12

    public static func bottomRight(screen: CGRect, width: CGFloat, height: CGFloat, margin: CGFloat, open: Bool) -> CGRect {
        let left = screen.maxX - width - margin
        let right = open ? screen.maxX + edgeThickness : screen.maxX - cornerGap
        let reach = open ? height : edgeThickness
        return CGRect(x: left, y: screen.minY - edgeThickness, width: right - left, height: reach + edgeThickness)
    }
}

public enum DrawerCloseStep: Equatable, Sendable {
    case closeThenRun
    case runAfterFade
    case drop
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
