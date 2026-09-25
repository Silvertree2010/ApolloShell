import Foundation

public enum UsableArea {
    public static func rect(visible: CGRect, bounds: CGRect, edge: NSEdgeInsets, extra: NSEdgeInsets) -> CGRect {
        let left = max(visible.minX, bounds.minX + edge.left) + extra.left
        let top = max(visible.minY, bounds.minY + edge.top) + extra.top
        let right = min(visible.maxX, bounds.maxX - edge.right) - extra.right
        let bottom = min(visible.maxY, bounds.maxY - edge.bottom) - extra.bottom
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
