import CoreGraphics

/// Where the bars of one screen stand, and how much room they keep from
/// other windows. Pure arithmetic in AppKit coordinates (origin at the bottom
/// left, y upwards), so it is testable without a screen.
///
/// The order of precedence: the top and bottom bars run the whole width of
/// the screen; the sidebar (left) and the right bar fit between them. That
/// way no two bars overlap, whatever combination is switched on.
public enum EdgeBarGeometry {
    /// Gap between an island and the screen edge in the island style.
    public static let islandMargin: CGFloat = 6

    /// What a bar needs from the geometry.
    public struct Bar: Equatable, Sendable {
        public var thickness: CGFloat
        public var style: BarStyle
        /// Top bar only: over Apple's menu bar instead of below it.
        public var coversMenuBar: Bool

        public init(thickness: CGFloat, style: BarStyle = .fill, coversMenuBar: Bool = true) {
            self.thickness = thickness
            self.style = style
            self.coversMenuBar = coversMenuBar
        }

        public init(_ bar: EdgeBar) {
            self.init(thickness: CGFloat(bar.thickness), style: bar.style, coversMenuBar: bar.coversMenuBar)
        }

        /// The panel's extent across the edge: the bar plus the island gap
        /// towards the screen edge.
        var extent: CGFloat { thickness + (style == .islands ? EdgeBarGeometry.islandMargin : 0) }
    }

    public struct Result: Equatable, Sendable {
        /// Panel frame per bar that is on.
        public var frames: [BarEdge: CGRect]
        /// The sidebar's column: from the bottom bar (or the screen edge) up
        /// to the top bar or the menu bar. Its width stays the sidebar's.
        public var sidebarMinY: CGFloat
        public var sidebarMaxY: CGFloat
        /// Room other windows keep from each edge, measured from the full
        /// screen frame. Top counts only a top bar that reaches below the
        /// menu bar - the menu bar itself macOS already keeps free.
        public var reserved: ReservedInsets
        /// How far the edge bars reach in from each edge of the full screen
        /// frame - the menu bar included when a top bar covers or sits
        /// below it. Unlike `reserved` it leaves out the sidebar: panels
        /// placed against the screen (Dashboard, Utilities, toasts) always
        /// reckoned with the sidebar on their own, and with no edge bar on
        /// they must land exactly where they did before edge bars existed.
        public var barInsets: ReservedInsets
    }

    /// - Parameters:
    ///   - screen: the whole screen frame.
    ///   - visibleTop: `visibleFrame.maxY`, the lower edge of the menu bar
    ///     (the screen's top edge when the menu bar is hidden).
    ///   - sidebarWidth: `nil` when this screen has no sidebar.
    public static func layout(screen: CGRect, visibleTop: CGFloat, sidebarWidth: CGFloat?,
                              bars: [BarEdge: Bar]) -> Result {
        var frames: [BarEdge: CGRect] = [:]
        let menuBar = max(screen.maxY - visibleTop, 0)

        var top = visibleTop
        if let bar = bars[.top] {
            let height: CGFloat
            let maxY: CGFloat
            if bar.coversMenuBar {
                // Never thinner than the menu bar it covers, or Apple's bar
                // would show below it.
                height = max(bar.extent, menuBar)
                maxY = screen.maxY
            } else {
                height = bar.extent
                maxY = visibleTop
            }
            let frame = CGRect(x: screen.minX, y: maxY - height, width: screen.width, height: height)
            frames[.top] = frame
            top = min(top, frame.minY)
        }

        var bottom = screen.minY
        if let bar = bars[.bottom] {
            let frame = CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: bar.extent)
            frames[.bottom] = frame
            bottom = frame.maxY
        }

        if let bar = bars[.right] {
            frames[.right] = CGRect(x: screen.maxX - bar.extent, y: bottom,
                                    width: bar.extent, height: max(top - bottom, 0))
        }

        let reserved = ReservedInsets(
            top: frames[.top].map { $0.minY < visibleTop - 0.5 ? screen.maxY - $0.minY : 0 } ?? 0,
            left: sidebarWidth ?? 0,
            bottom: frames[.bottom]?.height ?? 0,
            right: frames[.right]?.width ?? 0
        )
        let barInsets = ReservedInsets(
            top: frames[.top].map { screen.maxY - $0.minY } ?? 0,
            bottom: frames[.bottom]?.height ?? 0,
            right: frames[.right]?.width ?? 0
        )
        return Result(frames: frames, sidebarMinY: bottom, sidebarMaxY: top, reserved: reserved,
                      barInsets: barInsets)
    }

    /// The part of `visible` (the screen's `visibleFrame`) no edge bar
    /// covers: where panels that avoid the menu bar and Apple's Dock go
    /// (Nexus panel, desktop clock, edit mode toolbar). No bars: `visible`
    /// itself, untouched, so nothing moves by a rounding error.
    public static func usableFrame(visible: CGRect, screen: CGRect, bars: ReservedInsets) -> CGRect {
        guard !bars.isZero else { return visible }
        return inset(visible, within: screen, by: bars)
    }

    /// The part of the whole screen frame no edge bar covers: where panels
    /// that grow out of a screen edge (Dashboard, Utilities, Launcher,
    /// toasts) attach instead of the screen edge itself. No bars: `screen`.
    public static func barFreeFrame(screen: CGRect, bars: ReservedInsets) -> CGRect {
        guard !bars.isZero else { return screen }
        return inset(screen, within: screen, by: bars)
    }

    /// `rect` cut back wherever a bar, measured from the edges of `screen`,
    /// reaches into it. Never negative.
    private static func inset(_ rect: CGRect, within screen: CGRect, by bars: ReservedInsets) -> CGRect {
        let minX = max(rect.minX, screen.minX + bars.left)
        let maxX = min(rect.maxX, screen.maxX - bars.right)
        let minY = max(rect.minY, screen.minY + bars.bottom)
        let maxY = min(rect.maxY, screen.maxY - bars.top)
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))
    }
}
