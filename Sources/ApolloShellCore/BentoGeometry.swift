import Foundation

/// The geometry of the bento pages: a valid place, snapping, the scale. Plain
/// functions in reference points (a page of 839 x 392, `DashboardGeometry`).
/// No cells: Caelestia's measurements (130, 250, 275, 110 ...) fit into no
/// even grid, and the order comes from the snapping.
public enum BentoGeometry {
    public static let pageWidth = DashboardGeometry.width
    public static let pageHeight = DashboardGeometry.height
    /// The minimum gap between two widgets, Caelestia's grid gap.
    public static let spacing = DashboardGeometry.spacing
    /// Closer than this: the widget jumps onto the target.
    public static let snapDistance: Double = 8

    // MARK: Valid

    public static func isInside(_ frame: WidgetFrame) -> Bool {
        frame.x >= 0 && frame.y >= 0 && frame.maxX <= pageWidth && frame.maxY <= pageHeight
    }

    /// Closer than `spacing` on both axes, an overlap included. Exactly
    /// `spacing` apart is allowed; a diagonal offset only counts when both
    /// axes are too close.
    public static func tooClose(_ a: WidgetFrame, _ b: WidgetFrame) -> Bool {
        a.x < b.maxX + spacing && b.x < a.maxX + spacing
            && a.y < b.maxY + spacing && b.y < a.maxY + spacing
    }

    public static func isValid(_ frame: WidgetFrame, kind: WidgetKind, others: [WidgetFrame]) -> Bool {
        isInside(frame) && kind.allows(width: frame.width, height: frame.height)
            && !others.contains { tooClose(frame, $0) }
    }

    // MARK: Scale

    /// The width of the 14-inch MacBook: factor 1 there, everything as before 0.2.
    public static let referenceScreenWidth: Double = 1512
    public static let automaticRange: ClosedRange<Double> = 0.85...1.5
    /// The slider in Nexus.
    public static let userScaleRange: ClosedRange<Double> = 0.7...1.5

    public static func clampedUserScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, userScaleRange.lowerBound), userScaleRange.upperBound)
    }

    /// The scale for a screen: the automatic one by width times the slider,
    /// at most as big as lets the dashboard at reference size fit on the
    /// screen - `contentHeight` (with the page bar on top) into
    /// `availableHeight`, and `contentWidth` into the width of the screen.
    ///
    /// The width used not to count, because the automatic factor comes from
    /// the width anyway - but it has a floor of 0.85, and the slider
    /// multiplies on top of it: on a screen of 1110 pt at 1.5 the dashboard
    /// grew wider than the screen it stands on.
    public static func scale(screenWidth: Double, availableHeight: Double, contentHeight: Double,
                             contentWidth: Double = 0, userScale: Double) -> Double {
        let automatic = min(max(screenWidth / referenceScreenWidth, automaticRange.lowerBound), automaticRange.upperBound)
        var wanted = automatic * clampedUserScale(userScale)
        if contentHeight > 0 { wanted = min(wanted, availableHeight / contentHeight) }
        if contentWidth > 0 { wanted = min(wanted, screenWidth / contentWidth) }
        return wanted
    }

    // MARK: Snapping

    /// Dragging: per axis the widget jumps onto the nearest target closer than
    /// `snapDistance` - the page edge, the same line as another widget, or
    /// exactly `spacing` next to it. Without a target the axis stays. The
    /// result is rounded to whole points; whether it fits is said by `isValid`.
    public static func snapMove(_ proposed: WidgetFrame, others: [WidgetFrame]) -> WidgetFrame {
        var frame = proposed
        frame.x = snap(frame.x, to: startCandidates(length: frame.width, page: pageWidth,
                                                    others: others.map { (start: $0.x, end: $0.maxX) }))
        frame.y = snap(frame.y, to: startCandidates(length: frame.height, page: pageHeight,
                                                    others: others.map { (start: $0.y, end: $0.maxY) }))
        // Round only the place to whole points - the width and height stay as
        // they came in (some sizes of the performance page are half points,
        // 413.5 for instance; rounding would push them outside their range).
        frame.x = frame.x.rounded()
        frame.y = frame.y.rounded()
        return frame
    }

    /// Dragging the size (the handle at the bottom right, the top left corner
    /// stays): the height jumps to the next allowed one, the width stays in
    /// the range of that size and snaps at the page edge and at neighbours
    /// with flexible widgets (right edges flush or `spacing` before the neighbour).
    public static func snapResize(_ frame: WidgetFrame, kind: WidgetKind, proposedWidth: Double,
                                  proposedHeight: Double, others: [WidgetFrame]) -> WidgetFrame {
        guard let size = kind.sizes.min(by: { abs($0.height - proposedHeight) < abs($1.height - proposedHeight) })
        else { return frame }
        var width = min(max(proposedWidth, size.minWidth), size.maxWidth)
        if size.isFlexible {
            var candidates = [pageWidth - frame.x]
            for other in others {
                candidates += [other.x - spacing - frame.x, other.maxX - frame.x]
            }
            width = snap(width, to: candidates.filter { $0 >= size.minWidth && $0 <= size.maxWidth })
            // Round first, then force it back into the range of the size - a
            // half-point maximum (413.5, say) stays untouched that way instead
            // of becoming invalid through the rounding.
            width = min(max(width.rounded(), size.minWidth), size.maxWidth)
        }
        // A fixed width (minWidth == maxWidth) is the exact catalogue value
        // already - never round, otherwise 169.5 becomes invalid.
        return WidgetFrame(x: frame.x.rounded(), y: frame.y.rounded(), width: width, height: size.height)
    }

    /// A new widget out of Nexus: the smallest size, centred under the pointer
    /// (`x`, `y` in reference points), then snapped as when dragging.
    public static func dropFrame(kind: WidgetKind, x: Double, y: Double, others: [WidgetFrame]) -> WidgetFrame {
        let size = kind.smallestSize
        let proposed = WidgetFrame(x: x - size.minWidth / 2, y: y - size.height / 2,
                                   width: size.minWidth, height: size.height)
        return snapMove(proposed, others: others)
    }

    /// The first free place for the smallest size of a kind: rows from top to
    /// bottom, in them from left to right, over the candidates 0 and “right
    /// behind another widget" (`maxX`/`maxY` plus `spacing`) - the way the
    /// gallery places a widget that was clicked. `nil` when no place fits (the
    /// page is full).
    public static func firstFreeFrame(kind: WidgetKind, others: [WidgetFrame]) -> WidgetFrame? {
        let size = kind.smallestSize
        var xCandidates: Set<Double> = [0]
        var yCandidates: Set<Double> = [0]
        for other in others {
            xCandidates.insert(other.maxX + spacing)
            yCandidates.insert(other.maxY + spacing)
        }
        for y in yCandidates.sorted() {
            for x in xCandidates.sorted() {
                let frame = WidgetFrame(x: x, y: y, width: size.minWidth, height: size.height)
                if isValid(frame, kind: kind, others: others) { return frame }
            }
        }
        return nil
    }

    /// The possible starts on one axis: both page edges, the same line as
    /// another widget (start at start, end at end) and exactly `spacing`
    /// before or behind it.
    static func startCandidates(length: Double, page: Double, others: [(start: Double, end: Double)]) -> [Double] {
        var result = [0, page - length]
        for other in others {
            result += [other.start, other.end - length, other.end + spacing, other.start - spacing - length]
        }
        return result
    }

    static func snap(_ value: Double, to candidates: [Double]) -> Double {
        guard let best = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(best - value) < snapDistance else { return value }
        return best
    }
}
