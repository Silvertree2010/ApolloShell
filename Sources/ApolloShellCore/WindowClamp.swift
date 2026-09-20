import CoreGraphics

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
    /// Two cases, because they came about differently:
    /// - The left edge exactly at the screen edge: the system or the app put
    ///   it there (zoom, "fill", tile left, maximise). Then the right edge
    ///   stays put and the window gets narrower - the way those commands
    ///   reckon with a Dock docked on the left. Otherwise a left tile would
    ///   be pushed into the right one.
    /// - Otherwise (dragged halfway under it by hand, hanging over the left
    ///   edge): move it and keep the size. Only when it would then run past
    ///   the screen on the right, make it narrower - but never let it reach
    ///   further right than it already did.
    ///
    /// `minWidth` is the smallest width the app allows (learned from a
    /// refused shrink, otherwise 0). It never gets narrower than that; then
    /// it is only moved and the window reaches further right.
    public static func clampedFrame(
        window: CGRect,
        screen: CGRect,
        reservedWidth: CGFloat,
        minWidth: CGFloat = 0
    ) -> CGRect? {
        guard reservedWidth > 0, window.width > 0, window.height > 0 else { return nil }
        let limit = screen.minX + reservedWidth
        guard window.minX < limit - tolerance else { return nil }

        var result = window
        result.origin.x = limit

        let pinnedWidth = window.maxX - limit
        if abs(window.minX - screen.minX) <= tolerance, pinnedWidth > 0 {
            result.size.width = max(pinnedWidth, minWidth)
        } else {
            let rightLimit = max(screen.maxX, window.maxX)
            result.size.width = max(min(window.width, rightLimit - limit), minWidth)
        }
        return result
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
