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

    /// - Parameters:
    ///   - length: the room along the bar, from 0.
    ///   - start, center, end: the ideal length of each zone.
    ///   - notch: in the same coordinates as `length`.
    public static func place(length: CGFloat, start: CGFloat, center: CGFloat, end: CGFloat,
                             gap: CGFloat, notch: BarNotch? = nil) -> Placement {
        let length = max(length, 0)
        guard let notch else {
            return row(from: 0, to: length, start: start, center: center, end: end, gap: gap, centered: true)
        }
        // Left of the housing: the start zone alone, a gap short of it.
        let leftEnd = min(max(notch.leftEnd - gap, 0), length)
        let startLength = min(max(start, 0), leftEnd)
        // Right of it: centre and end.
        let rightStart = min(max(notch.rightStart + gap, 0), length)
        let right = row(from: rightStart, to: length, start: 0, center: center, end: end, gap: gap, centered: false)
        return Placement(start: Span(origin: 0, length: startLength), center: right.center, end: right.end)
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
