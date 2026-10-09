import CoreGraphics

public enum SidebarBleed {
    public static let depth: CGFloat = 30

    public static func edges(screen: CGRect, others: [CGRect], depth: CGFloat = depth) -> (left: CGFloat, bottom: CGFloat) {
        let rest = others.filter { $0 != screen }
        func free(_ r: CGRect) -> Bool { !rest.contains { $0.intersects(r) } }
        let left = free(CGRect(x: screen.minX - depth, y: screen.minY, width: depth, height: screen.height)) ? depth : 0
        let below = CGRect(x: screen.minX - left, y: screen.minY - depth, width: screen.width + left, height: depth)
        return (left, free(below) ? depth : 0)
    }
}
