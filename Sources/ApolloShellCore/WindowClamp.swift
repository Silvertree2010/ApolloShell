import CoreGraphics

/// How much of the top and left screen edges the shell reserves, in
/// accessibility coordinates: the menu bar at the top, the sidebar at the
/// left. No bar sits at the bottom or the right, so those edges are never
/// reserved. An edge left at 0 is left alone entirely by `WindowClamp`,
/// rather than pulling in a window that merely happens to sit off-screen
/// there.
public struct ReservedInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat

    public init(top: CGFloat = 0, left: CGFloat = 0) {
        self.top = top
        self.left = left
    }

    public static let zero = ReservedInsets()

    public var isZero: Bool {
        top == 0 && left == 0
    }

    /// The larger reservation per edge. The window watch knows screens by
    /// `ScreenInfo.key`, which two identical screens share; when their bars
    /// differ, keeping the larger strip on both never lets a window run
    /// under a bar (the sidebar alone did the same with its set of keys).
    public func union(_ other: ReservedInsets) -> ReservedInsets {
        ReservedInsets(top: max(top, other.top), left: max(left, other.left))
    }
}

/// Geometry for the window watch: other apps' windows should not run under
/// the left bar, just as they do not run under the Dock.
///
/// macOS knows no interface for reserving screen space (`visibleFrame`
/// belongs to the Dock and the menu bar alone). The app therefore pushes
/// windows aside afterwards through the accessibility API; only the plain
/// arithmetic lives here, so it is testable without windows.
///
/// All rectangles in ONE coordinate system. The app works in accessibility
/// coordinates (origin at the top left of the main screen, y downwards),
/// because window position and size arrive that way. For the nudging itself
/// the direction of y does not matter: it only changes x and the width.
public enum WindowClamp {
    /// Ignore fractions of a point: apps like to round positions to whole
    /// points, otherwise a window at x = 43.5 would be pushed forever.
    public static let tolerance: CGFloat = 0.5

    /// A new frame for a window that reaches into the reserved strip at the
    /// left edge of `screen`, or `nil` when there is nothing to do.
    ///
    /// Kept as a thin wrapper: the left bar was the first bar the watch grew,
    /// and its callers and tests should not have to learn `ReservedInsets`
    /// just to reserve one edge.
    public static func clampedFrame(
        window: CGRect,
        screen: CGRect,
        reservedWidth: CGFloat,
        minWidth: CGFloat = 0
    ) -> CGRect? {
        clampedFrame(
            window: window,
            screen: screen,
            insets: ReservedInsets(left: reservedWidth),
            minSize: CGSize(width: minWidth, height: 0)
        )
    }

    /// A new frame for a window that reaches into the strip reserved at the
    /// top (menu bar) or the left (sidebar) of the screen, or `nil` when
    /// there is nothing to do. Both at once work too: a maximised window
    /// ends up exactly in the free rect below the menu bar and right of the
    /// sidebar.
    ///
    /// Coordinates are accessibility coordinates (origin top left, y
    /// downwards): `insets.top` therefore limits `minY` just as
    /// `insets.left` limits `minX`.
    ///
    /// Each axis follows the same two-case rule:
    /// - The window's edge exactly at the screen edge: the system or the
    ///   app put it there (zoom, "fill", tile, maximise). Then the opposite
    ///   edge stays put and the window shrinks - the way those commands
    ///   reckon with a bar docked at that edge. Otherwise a left tile would
    ///   be pushed into the right one.
    /// - Otherwise (dragged halfway under it by hand, hanging over the
    ///   edge): move it and keep the size. Only when it would then run past
    ///   the opposite screen edge, make it smaller - but never let it reach
    ///   further than it already did.
    ///
    /// `minSize` is the smallest size the app allows (learned from a
    /// refused shrink, otherwise `.zero`). Neither dimension ever gets
    /// smaller than that; then the window is only moved and reaches further
    /// in the direction it was shrinking towards.
    public static func clampedFrame(
        window: CGRect,
        screen: CGRect,
        insets: ReservedInsets,
        minSize: CGSize = .zero
    ) -> CGRect? {
        guard !insets.isZero, window.width > 0, window.height > 0 else { return nil }

        let x = clampedAxis(
            windowLow: window.minX, windowHigh: window.maxX,
            screenLow: screen.minX, screenHigh: screen.maxX,
            inset: insets.left, minLength: minSize.width
        )
        let y = clampedAxis(
            windowLow: window.minY, windowHigh: window.maxY,
            screenLow: screen.minY, screenHigh: screen.maxY,
            inset: insets.top, minLength: minSize.height
        )
        guard x != nil || y != nil else { return nil }

        let result = CGRect(
            x: x?.low ?? window.minX,
            y: y?.low ?? window.minY,
            width: x?.length ?? window.width,
            height: y?.length ?? window.height
        )
        return isSameFrame(result, window) ? nil : result
    }

    /// One axis (x with the sidebar, or y with the menu bar) of
    /// `clampedFrame`. `nil` when this axis needs no change. An `inset` of 0
    /// means no bar sits at that edge, so it is never a reason to move or
    /// shrink the window.
    private static func clampedAxis(
        windowLow: CGFloat,
        windowHigh: CGFloat,
        screenLow: CGFloat,
        screenHigh: CGFloat,
        inset: CGFloat,
        minLength: CGFloat
    ) -> (low: CGFloat, length: CGFloat)? {
        let limit = screenLow + inset
        guard inset > 0, windowLow < limit - tolerance else { return nil }

        let pinnedLength = windowHigh - limit
        if abs(windowLow - screenLow) <= tolerance, pinnedLength > 0 {
            return (limit, max(pinnedLength, minLength))
        }
        let bound = max(screenHigh, windowHigh)
        return (limit, max(min(windowHigh - windowLow, bound - limit), minLength))
    }

    /// Index of the screen that holds the largest part of the window, or
    /// `nil` when it lies on none. Only windows of the main screen are
    /// nudged; one that reaches over with just a corner from a screen to the
    /// left belongs to that one.
    public static func dominantScreen(for window: CGRect, among screens: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = window.intersection(screen)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) {
                best = (index, area)
            }
        }
        return best?.index
    }

    /// AppKit (origin at the bottom left, y upwards) <-> accessibility
    /// (origin at the top left of the main screen, y downwards). The mapping
    /// is its own inverse, hence one function for both directions.
    /// `primaryHeight` is the height of the screen with the menu bar.
    public static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Equal but for rounding.
    public static func isSameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

/// Remembers per window what the watch did last, so it does not lock itself
/// into a loop with an app or with itself.
///
/// - Echo: our own move sets off "moved" notifications again. When the window
///   still stands exactly where it stood after the last intervention, nobody
///   moved it - do nothing. What is stored is the frame READ afterwards, not
///   the wanted one: an app that only half gives in (a minimum width, say)
///   should not be nudged over and over.
/// - Resistance: some apps put their window straight back. More than
///   `maxAttempts` interventions within `period` seconds, then quiet until
///   the deadline has passed.
public struct ClampLedger<Key: Hashable> {
    public var maxAttempts: Int
    public var period: Double

    private var lastFrames: [Key: CGRect] = [:]
    private var attempts: [Key: [Double]] = [:]

    public init(maxAttempts: Int = 3, period: Double = 5) {
        self.maxAttempts = maxAttempts
        self.period = period
    }

    /// May the window (with this current frame) be touched right now?
    /// `now` in seconds on any monotonically rising clock.
    public mutating func shouldClamp(_ key: Key, current: CGRect, now: Double) -> Bool {
        if let last = lastFrames[key], WindowClamp.isSameFrame(last, current) {
            return false
        }
        // Throw away expired attempts; do not store empty entries in the
        // first place, otherwise the book grows with every window ever seen.
        let recent = (attempts[key] ?? []).filter { now - $0 < period }
        attempts[key] = recent.isEmpty ? nil : recent
        return recent.count < maxAttempts
    }

    /// After an intervention: remember the frame read afterwards.
    public mutating func record(_ key: Key, result: CGRect, now: Double) {
        lastFrames[key] = result
        attempts[key, default: []].append(now)
    }

    /// Window closed or app ended.
    public mutating func forget(_ key: Key) {
        lastFrames[key] = nil
        attempts[key] = nil
    }

    public mutating func forget(where predicate: (Key) -> Bool) {
        for key in lastFrames.keys where predicate(key) { lastFrames[key] = nil }
        for key in attempts.keys where predicate(key) { attempts[key] = nil }
    }

    /// How many windows are remembered right now (for tests and the log).
    public var count: Int { Set(lastFrames.keys).union(attempts.keys).count }
}
