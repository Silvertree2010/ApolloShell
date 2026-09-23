import CoreGraphics

/// Where the camera housing cuts the top edge of a screen, as lengths along a
/// top bar (0 = the bar's left end). Only a bar that lies over the menu bar
/// meets it; one below the menu bar never does.
public struct BarNotch: Equatable, Sendable {
    /// End of the usable room left of the housing.
    public var leftEnd: CGFloat
    /// Start of the usable room right of the housing.
    public var rightStart: CGFloat

    public init(leftEnd: CGFloat, rightStart: CGFloat) {
        self.leftEnd = leftEnd
        self.rightStart = rightStart
    }

    /// From `NSScreen.auxiliaryTopLeftArea`/`auxiliaryTopRightArea` (screen
    /// coordinates). `nil` when either is missing or they touch - a screen
    /// without a housing reports none or one seamless strip.
    public init?(screenMinX: CGFloat, leftArea: CGRect?, rightArea: CGRect?) {
        guard let leftArea, let rightArea, rightArea.minX - leftArea.maxX > 1 else { return nil }
        self.init(leftEnd: leftArea.maxX - screenMinX, rightStart: rightArea.minX - screenMinX)
    }

    /// The same housing measured from a point `offset` further along - the
    /// zones start after the bar's own margin, not at the screen edge.
    public func shifted(by offset: CGFloat) -> BarNotch {
        BarNotch(leftEnd: leftEnd - offset, rightStart: rightStart - offset)
    }
}

/// Where the three zones of a bar go along its length. Pure arithmetic, so the
/// rules below are tested without a view.
///
/// - The end zone has the first claim (status, power: the things one looks
///   for at a fixed spot), then the centre, and the start zone gets what is
///   left - too long a start is cut off, never pushed over the others.
/// - The centre stands truly in the middle of the bar when there is room;
///   otherwise it moves aside just enough that nothing overlaps (at least
///   `gap` from its neighbours).
/// - With a notch the start zone may only use the room left of the housing;
///   centre and end go right of it. The centre then follows the housing
///   directly (like SketchyBar's "e" position): the middle of the screen is
///   hidden behind the camera, and the spot right next to it is the closest
///   thing to a centre that can be seen.
/// - Empty zones take no room and no gap.
/// - A zone holding flexible modules (Dock, spacer) takes the room that is
///   left over, like `BarFlex` does inside one bar: every flexible module
///   gets an equal share of it, and a zone grows by the shares of the
///   modules it holds. Start and end grow towards the centre; a flexible
///   centre grows evenly on both sides so it stays in the middle, and only
///   takes the lopsided rest when not even its natural length fits there.
///   Without the share a Dock in a zone measured 0 and vanished.
public enum EdgeBarZoneLayout {
    public struct Span: Equatable, Sendable {
        public var origin: CGFloat
        public var length: CGFloat

        public init(origin: CGFloat, length: CGFloat) {
            self.origin = origin
            self.length = length
        }

        public var end: CGFloat { origin + length }
    }

    public struct Placement: Equatable, Sendable {
        public var start: Span
        public var center: Span
        public var end: Span
    }

    /// How many flexible modules (Dock, spacer) each zone holds. Zero
    /// everywhere is the plain layout of fixed zones.
    public struct Flexible: Equatable, Sendable {
        public var start: Int
        public var center: Int
        public var end: Int

        public init(start: Int = 0, center: Int = 0, end: Int = 0) {
            self.start = max(start, 0)
            self.center = max(center, 0)
            self.end = max(end, 0)
        }

        public static let none = Flexible()

        var total: Int { start + center + end }
    }

    /// - Parameters:
    ///   - length: the room along the bar, from 0.
    ///   - start, center, end: the natural length of each zone (flexible
    ///     modules counted as 0, the way `BarStack` measures them).
    ///   - notch: in the same coordinates as `length`.
    ///   - flexible: which zones hold flexible modules and how many.
    public static func place(length: CGFloat, start: CGFloat, center: CGFloat, end: CGFloat,
                             gap: CGFloat, notch: BarNotch? = nil, flexible: Flexible = .none) -> Placement {
        let length = max(length, 0)
        guard let notch else {
            let base = row(from: 0, to: length, start: start, center: center, end: end, gap: gap, centered: true)
            return grow(base, from: 0, to: length, flexible: flexible, gap: gap, centered: true)
        }
        // Left of the housing: the start zone alone, a gap short of it. A
        // flexible start takes all of that room - nothing else may use it.
        let leftEnd = min(max(notch.leftEnd - gap, 0), length)
        let startLength = flexible.start > 0 ? leftEnd : min(max(start, 0), leftEnd)
        // Right of it: centre and end, the centre right next to the housing.
        let rightStart = min(max(notch.rightStart + gap, 0), length)
        let right = grow(
            row(from: rightStart, to: length, start: 0, center: center, end: end, gap: gap, centered: false),
            from: rightStart, to: length, flexible: Flexible(center: flexible.center, end: flexible.end),
            gap: gap, centered: false
        )
        return Placement(start: Span(origin: 0, length: startLength), center: right.center, end: right.end)
    }

    /// The modules of one zone (or the groups of one zone) in a row: fixed
    /// ones keep their natural length, flexible ones get their natural length
    /// plus an equal share of what is left per flexible module (`weights`,
    /// 0 = fixed). Too little room: everyone keeps the natural length and
    /// the zone clips, like the fixed zones do.
    public static func stack(naturals: [CGFloat], weights: [Int], length: CGFloat, spacing: CGFloat) -> [Span] {
        let total = weights.reduce(0) { $0 + max($1, 0) }
        let used = naturals.reduce(0) { $0 + max($1, 0) } + CGFloat(max(naturals.count - 1, 0)) * spacing
        let share = total > 0 ? max(length - used, 0) / CGFloat(total) : 0
        var origin: CGFloat = 0
        return naturals.enumerated().map { index, natural in
            let weight = index < weights.count ? max(weights[index], 0) : 0
            let span = Span(origin: origin, length: max(natural, 0) + share * CGFloat(weight))
            origin = span.end + spacing
            return span
        }
    }

    /// Hands the room `row` left over to the flexible zones. `base` is the
    /// layout at natural lengths; its lengths are the least each zone keeps.
    private static func grow(_ base: Placement, from lo: CGFloat, to hi: CGFloat, flexible: Flexible,
                             gap: CGFloat, centered: Bool) -> Placement {
        let total = flexible.total
        guard total > 0 else { return base }
        // A flexible zone counts as present even at natural length 0: a Dock
        // alone still wants its gap to the neighbours.
        let hasStart = base.start.length > 0 || flexible.start > 0
        let hasCenter = base.center.length > 0 || flexible.center > 0
        let hasEnd = base.end.length > 0 || flexible.end > 0
        let present = [hasStart, hasCenter, hasEnd].filter { $0 }.count
        let natural = base.start.length + base.center.length + base.end.length
        let free = (hi - lo) - natural - CGFloat(max(present - 1, 0)) * gap
        guard free > 0 else { return base }
        let share = free / CGFloat(total)

        var result = base
        if flexible.center > 0 {
            // The centre's slot, with start and end at their least.
            let low = lo + base.start.length + (hasStart ? gap : 0)
            let high = hi - base.end.length - (hasEnd ? gap : 0)
            var length = base.center.length + share * CGFloat(flexible.center)
            let origin: CGFloat
            if centered {
                let mid = (lo + hi) / 2
                let widest = 2 * min(mid - low, high - mid)
                if widest >= base.center.length {
                    length = min(length, widest)
                    origin = mid - length / 2
                } else {
                    origin = min(max(mid - length / 2, low), high - length)
                }
            } else {
                origin = low
            }
            result.center = Span(origin: origin, length: length)
        }
        if flexible.start > 0 {
            let limit: CGFloat
            if hasCenter {
                limit = result.center.origin - gap
            } else if hasEnd {
                limit = hi - base.end.length - share * CGFloat(flexible.end) - gap
            } else {
                limit = hi
            }
            result.start = Span(origin: lo, length: max(limit - lo, base.start.length))
        }
        if flexible.end > 0 {
            let limit: CGFloat
            if hasCenter {
                limit = result.center.end + gap
            } else if hasStart {
                limit = result.start.end + gap
            } else {
                limit = lo
            }
            let length = max(hi - limit, base.end.length)
            result.end = Span(origin: hi - length, length: length)
        }
        return result
    }

    /// Three zones between `lo` and `hi`. `centered`: the centre aims at the
    /// middle, otherwise at the lowest spot it may take.
    private static func row(from lo: CGFloat, to hi: CGFloat, start: CGFloat, center: CGFloat, end: CGFloat,
                            gap: CGFloat, centered: Bool) -> Placement {
        let room = max(hi - lo, 0)
        let endLength = min(max(end, 0), room)
        let centerGap: CGFloat = endLength > 0 && center > 0 ? gap : 0
        let centerLength = min(max(center, 0), max(room - endLength - centerGap, 0))
        // What the centre and the end occupy, with the gap between them.
        let taken = endLength + centerLength + (endLength > 0 && centerLength > 0 ? gap : 0)
        let startRoom = max(room - taken - (taken > 0 ? gap : 0), 0)
        let startLength = min(max(start, 0), startRoom)

        // The centre's slot: after the start (plus gap) and before the end
        // (plus gap). The construction above guarantees low <= high.
        let low = lo + startLength + (startLength > 0 ? gap : 0)
        let high = hi - endLength - (endLength > 0 ? gap : 0) - centerLength
        let ideal = centered ? lo + (room - centerLength) / 2 : low
        let centerOrigin = centerLength > 0 ? min(max(ideal, low), high) : low

        return Placement(start: Span(origin: lo, length: startLength),
                         center: Span(origin: centerOrigin, length: centerLength),
                         end: Span(origin: hi - endLength, length: endLength))
    }
}

/// Where the detail window of a status icon in an edge bar goes (Wi-Fi,
/// Bluetooth, battery). The sidebar grows its popout out of its own glass;
/// an edge bar opens a plain panel next to the bar instead, so this only has
/// to say where. AppKit coordinates (y up).
///
/// - Top bar: below the bar, bottom bar: above it, right bar: left of it -
///   `gap` off the bar's inner edge, never over it.
/// - Along the bar it centres on the icon, but stays `margin` inside the
///   screen: a Wi-Fi icon in the far corner still opens a whole window.
public enum EdgeBarPopoutPlacement {
    public static func frame(icon: CGRect, bar: CGRect, size: CGSize, edge: BarEdge, screen: CGRect,
                             gap: CGFloat = 6, margin: CGFloat = 8) -> CGRect {
        func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            // A window wider than the screen keeps its start on screen.
            max(lo, min(value, hi))
        }
        switch edge {
        case .top, .bottom:
            let x = clamp(icon.midX - size.width / 2, screen.minX + margin, screen.maxX - margin - size.width)
            let y = edge == .top ? bar.minY - gap - size.height : bar.maxY + gap
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        case .right:
            let y = clamp(icon.midY - size.height / 2, screen.minY + margin, screen.maxY - margin - size.height)
            return CGRect(x: bar.minX - gap - size.width, y: y, width: size.width, height: size.height)
        }
    }
}
