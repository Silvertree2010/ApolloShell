import CoreGraphics

public struct BarNotch: Equatable, Sendable {
    public var leftEnd: CGFloat
    public var rightStart: CGFloat

    public init(leftEnd: CGFloat, rightStart: CGFloat) {
        self.leftEnd = leftEnd
        self.rightStart = rightStart
    }

    public init?(screenMinX: CGFloat, leftArea: CGRect?, rightArea: CGRect?) {
        guard let leftArea, let rightArea, rightArea.minX - leftArea.maxX > 1 else { return nil }
        self.init(leftEnd: leftArea.maxX - screenMinX, rightStart: rightArea.minX - screenMinX)
    }

    public func shifted(by offset: CGFloat) -> BarNotch {
        BarNotch(leftEnd: leftEnd - offset, rightStart: rightStart - offset)
    }
}

public enum MenuBarZoneLayout {
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

    public static func place(length: CGFloat, start: CGFloat, center: CGFloat, end: CGFloat,
                             gap: CGFloat, notch: BarNotch? = nil, flexible: Flexible = .none) -> Placement {
        let length = max(length, 0)
        guard let notch else {
            let base = row(from: 0, to: length, start: start, center: center, end: end, gap: gap, centered: true)
            return grow(base, from: 0, to: length, flexible: flexible, gap: gap, centered: true)
        }
        let leftEnd = min(max(notch.leftEnd - gap, 0), length)
        let startLength = flexible.start > 0 ? leftEnd : min(max(start, 0), leftEnd)
        let rightStart = min(max(notch.rightStart + gap, 0), length)
        let right = grow(
            row(from: rightStart, to: length, start: 0, center: center, end: end, gap: gap, centered: false),
            from: rightStart, to: length, flexible: Flexible(center: flexible.center, end: flexible.end),
            gap: gap, centered: false
        )
        return Placement(start: Span(origin: 0, length: startLength), center: right.center, end: right.end)
    }

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

    private static func grow(_ base: Placement, from lo: CGFloat, to hi: CGFloat, flexible: Flexible,
                             gap: CGFloat, centered: Bool) -> Placement {
        let total = flexible.total
        guard total > 0 else { return base }
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

    private static func row(from lo: CGFloat, to hi: CGFloat, start: CGFloat, center: CGFloat, end: CGFloat,
                            gap: CGFloat, centered: Bool) -> Placement {
        let room = max(hi - lo, 0)
        let endLength = min(max(end, 0), room)
        let centerGap: CGFloat = endLength > 0 && center > 0 ? gap : 0
        let centerLength = min(max(center, 0), max(room - endLength - centerGap, 0))
        let taken = endLength + centerLength + (endLength > 0 && centerLength > 0 ? gap : 0)
        let startRoom = max(room - taken - (taken > 0 ? gap : 0), 0)
        let startLength = min(max(start, 0), startRoom)

        let low = lo + startLength + (startLength > 0 ? gap : 0)
        let high = hi - endLength - (endLength > 0 ? gap : 0) - centerLength
        let ideal = centered ? lo + (room - centerLength) / 2 : low
        let centerOrigin = centerLength > 0 ? min(max(ideal, low), high) : low

        return Placement(start: Span(origin: lo, length: startLength),
                         center: Span(origin: centerOrigin, length: centerLength),
                         end: Span(origin: hi - endLength, length: endLength))
    }
}

public enum MenuBarPopoutPlacement {
    public static func frame(icon: CGRect, bar: CGRect, size: CGSize, screen: CGRect,
                             gap: CGFloat = 6, margin: CGFloat = 8) -> CGRect {
        let x = max(screen.minX + margin, min(icon.midX - size.width / 2, screen.maxX - margin - size.width))
        return CGRect(x: x, y: bar.minY - gap - size.height, width: size.width, height: size.height)
    }
}
