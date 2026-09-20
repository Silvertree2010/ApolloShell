import CoreGraphics

/// Where the two floating windows of the edit mode stand: pure arithmetic,
/// so the cases that need a screen nobody has to hand - a 13" panel, a
/// control centre grown tall - can be checked in a test instead of only in
/// a live session (`EditModeWindows` hands the measured rectangles in).
///
/// The screen rectangle is AppKit's: y counts upwards, `minY` is the bottom
/// edge.
public enum EditModeGeometry {
    /// Bottom centre, 20 pt above the lower edge; if the control centre
    /// stands in the way there, above its top edge instead - but never so
    /// high that the toolbar leaves the screen.
    ///
    /// The middle is the middle of the screen, not of the free area: with
    /// Apple's Dock at the left or right edge the two differ, and the
    /// toolbar has stood in the middle of the screen since 0.2.
    public static func toolbarCenter(screen: CGRect, visible: CGRect, size: CGSize, utilities: CGRect?) -> CGPoint {
        let bottom = visible.minY + 20
        var center = CGPoint(x: screen.midX, y: bottom + size.height / 2)
        let rect = CGRect(x: center.x - size.width / 2, y: bottom, width: size.width, height: size.height)
        if let utilities, utilities.intersects(rect.insetBy(dx: -8, dy: -8)) {
            center.y = utilities.maxY + 16 + size.height / 2
        }
        let highest = visible.maxY - size.height / 2
        center.y = min(center.y, highest)
        return center
    }

    /// How wide the gallery may be on this screen: its own width where
    /// there is room, otherwise narrow enough to stand beside the control
    /// centre instead of over it - but never below `minimum`, where the
    /// grid would have too few columns left to be a grid.
    ///
    /// The panel stands at the right edge, so what is free is everything
    /// left of it, less the same 16 pt of air the dashboard keeps.
    public static func galleryWidth(visible: CGRect, utilities: CGRect?, preferred: CGFloat,
                                    minimum: CGFloat) -> CGFloat {
        guard let utilities, utilities.height > 0 else { return min(preferred, visible.width) }
        let free = utilities.minX - visible.minX - 2 * 16
        return max(min(preferred, free), min(minimum, visible.width))
    }

    /// How many tiles of `tile` points fit side by side into a gallery of
    /// this width, at most `maximum` and at least one.
    public static func galleryColumns(width: CGFloat, margin: CGFloat, tile: CGFloat,
                                      spacing: CGFloat, maximum: Int) -> Int {
        let content = width - 2 * margin
        guard content > 0 else { return 1 }
        let fits = Int(((content + spacing) / (tile + spacing)).rounded(.down))
        return min(max(fits, 1), maximum)
    }

    /// Centred between the lower edge of the dashboard and the toolbar; in
    /// the middle of the screen while no dashboard is open. Too little room
    /// there (a large scale): directly above the toolbar. Sideways it keeps
    /// clear of the control centre, which stands at the right edge - on a
    /// narrow screen the gallery used to reach into it, and the control
    /// centre then lay under it.
    public static func galleryCenter(visible: CGRect, gallery: CGSize, dashboard: CGRect?,
                                     utilities: CGRect?, toolbarHeight: CGFloat) -> CGPoint {
        var y = visible.midY
        if let dashboard {
            let top = min(dashboard.minY, visible.maxY) - 16
            let bottom = visible.minY + 20 + toolbarHeight + 16
            y = top - bottom >= gallery.height ? (top + bottom) / 2 : bottom + gallery.height / 2
        }
        var x = visible.midX
        if let utilities, utilities.height > 0 {
            let rows = CGRect(x: x - gallery.width / 2, y: y - gallery.height / 2,
                              width: gallery.width, height: gallery.height)
            if utilities.intersects(rows) {
                // Left of the panel, with the same 16 pt of air the
                // dashboard gets - and not past the left edge of the screen.
                let wanted = utilities.minX - 16 - gallery.width / 2
                x = max(wanted, visible.minX + gallery.width / 2)
            }
        }
        return CGPoint(x: x, y: y)
    }
}
