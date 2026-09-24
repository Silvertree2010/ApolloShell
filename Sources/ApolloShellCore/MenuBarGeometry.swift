import CoreGraphics

/// Where the menu bar of one screen stands, and how much room the bars keep
/// from other windows. Pure arithmetic in AppKit coordinates (origin at the
/// bottom left, y upwards), so it is testable without a screen.
///
/// The menu bar runs the whole width of the screen; the sidebar's column
/// runs from the screen's bottom edge up to it. That way the two never
/// overlap.
public enum MenuBarGeometry {
    /// Gap between an island and the screen edge in the island style.
    public static let islandMargin: CGFloat = 6

    /// What the bar needs from the geometry.
    public struct Bar: Equatable, Sendable {
        public var thickness: CGFloat
        public var style: BarStyle
        /// Over Apple's menu bar instead of below it.
        public var coversMenuBar: Bool

        public init(thickness: CGFloat, style: BarStyle = .fill, coversMenuBar: Bool = true) {
            self.thickness = thickness
            self.style = style
            self.coversMenuBar = coversMenuBar
        }

        public init(_ bar: ApolloMenuBar) {
            self.init(thickness: CGFloat(bar.thickness), style: bar.style, coversMenuBar: bar.coversMenuBar)
        }

        /// The panel's height: the bar plus the island gap towards the top
        /// edge of the screen.
        var extent: CGFloat { thickness + (style == .islands ? MenuBarGeometry.islandMargin : 0) }
    }

    public struct Result: Equatable, Sendable {
        /// The menu bar's panel frame, `nil` when it is off on this screen.
        public var frame: CGRect?
        /// The top of the sidebar's column: the menu bar's lower edge, or
        /// Apple's menu bar without one. It always starts at the screen's
        /// bottom edge, and its width stays the sidebar's.
        public var sidebarMaxY: CGFloat
        /// Room other windows keep from each edge, measured from the full
        /// screen frame. Top counts only a menu bar that reaches below
        /// Apple's - that one macOS already keeps free.
        public var reserved: ReservedInsets
        /// How far the menu bar reaches down from the top of the full screen
        /// frame - Apple's menu bar included, whether the bar covers it or
        /// sits below it. Unlike `reserved` it leaves out the sidebar: panels
        /// placed against the screen (Dashboard, Utilities, toasts) always
        /// reckoned with the sidebar on their own, and with the menu bar off
        /// they must land exactly where they did before it existed.
        public var barInset: CGFloat
    }

    /// - Parameters:
    ///   - screen: the whole screen frame.
    ///   - visibleTop: `visibleFrame.maxY`, the lower edge of Apple's menu
    ///     bar (the screen's top edge when the menu bar is hidden).
    ///   - sidebarWidth: `nil` when this screen has no sidebar.
    ///   - bar: `nil` when this screen has no menu bar.
    public static func layout(screen: CGRect, visibleTop: CGFloat, sidebarWidth: CGFloat?,
                              bar: Bar?) -> Result {
        let appleMenuBar = max(screen.maxY - visibleTop, 0)
        var frame: CGRect?
        if let bar {
            let height: CGFloat
            let maxY: CGFloat
            if bar.coversMenuBar {
                // Never thinner than the menu bar it covers, or Apple's bar
                // would show below it.
                height = max(bar.extent, appleMenuBar)
                maxY = screen.maxY
            } else {
                height = bar.extent
                maxY = visibleTop
            }
            frame = CGRect(x: screen.minX, y: maxY - height, width: screen.width, height: height)
        }
        let top = min(visibleTop, frame?.minY ?? visibleTop)
        let reserved = ReservedInsets(
            top: frame.map { $0.minY < visibleTop - 0.5 ? screen.maxY - $0.minY : 0 } ?? 0,
            left: sidebarWidth ?? 0
        )
        return Result(frame: frame, sidebarMaxY: top, reserved: reserved,
                      barInset: frame.map { screen.maxY - $0.minY } ?? 0)
    }

    /// The part of `visible` (the screen's `visibleFrame`) the menu bar does
    /// not cover: where panels that avoid Apple's menu bar and Dock go
    /// (Nexus panel, desktop clock, edit mode toolbar). No bar: `visible`
    /// itself, untouched, so nothing moves by a rounding error.
    public static func usableFrame(visible: CGRect, screen: CGRect, barInset: CGFloat) -> CGRect {
        guard barInset > 0 else { return visible }
        return below(visible, screen: screen, barInset: barInset)
    }

    /// The part of the whole screen frame the menu bar does not cover: where
    /// panels that grow out of the top edge (Dashboard) attach instead of the
    /// screen edge itself. No bar: `screen`.
    public static func barFreeFrame(screen: CGRect, barInset: CGFloat) -> CGRect {
        guard barInset > 0 else { return screen }
        return below(screen, screen: screen, barInset: barInset)
    }

    /// `rect` cut back where the menu bar, measured from the top of
    /// `screen`, reaches into it. Never negative.
    private static func below(_ rect: CGRect, screen: CGRect, barInset: CGFloat) -> CGRect {
        let maxY = min(rect.maxY, screen.maxY - barInset)
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(maxY - rect.minY, 0))
    }
}
