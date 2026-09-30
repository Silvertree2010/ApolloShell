import Foundation

public struct CanvasFrame: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public init?(_ value: Value) {
        guard case .record(let record) = value,
              case .number(let x)? = record["x"], case .number(let y)? = record["y"],
              case .number(let width)? = record["width"], case .number(let height)? = record["height"],
              [x, y, width, height].allSatisfy(\.isFinite) else { return nil }
        self.init(x: x, y: y, width: width, height: height)
    }

    public var value: Value {
        .record(Record([("x", .number(x)), ("y", .number(y)), ("width", .number(width)), ("height", .number(height))]))
    }
}

public struct CanvasSize: Equatable, Hashable, Sendable {
    public var minWidth: Double
    public var maxWidth: Double
    public var height: Double

    public init(minWidth: Double, maxWidth: Double, height: Double) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.height = height
    }

    public var isFlexible: Bool { maxWidth > minWidth }

    public func allows(width: Double, height: Double) -> Bool {
        height == self.height && width >= minWidth && width <= maxWidth
    }

    public static func list(_ value: Value?) -> [CanvasSize] {
        guard case .list(let items)? = value else { return [] }
        return items.compactMap { item in
            guard case .record(let record) = item, case .number(let height)? = record["height"], height.isFinite else { return nil }
            let fixed = record["width"].flatMap { if case .number(let n) = $0 { n } else { nil } }
            let low = record["min-width"].flatMap { if case .number(let n) = $0 { n } else { nil } } ?? fixed
            let high = record["max-width"].flatMap { if case .number(let n) = $0 { n } else { nil } } ?? fixed ?? low
            guard let low, let high, low.isFinite, high.isFinite, high >= low else { return nil }
            return CanvasSize(minWidth: low, maxWidth: high, height: height)
        }
    }
}

public struct CanvasGeometry: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var gap: Double
    public var snapDistance: Double

    public static let referenceScreenWidth: Double = 1512
    public static let automaticRange: ClosedRange<Double> = 0.85...1.5
    public static let userScaleRange: ClosedRange<Double> = 0.7...1.5

    public init(width: Double, height: Double, gap: Double = 12, snap: Double = 8) {
        self.width = width
        self.height = height
        self.gap = gap
        self.snapDistance = snap
    }

    public func isInside(_ frame: CanvasFrame) -> Bool {
        frame.x >= 0 && frame.y >= 0 && frame.maxX <= width && frame.maxY <= height
    }

    public func tooClose(_ a: CanvasFrame, _ b: CanvasFrame) -> Bool {
        a.x < b.maxX + gap && b.x < a.maxX + gap && a.y < b.maxY + gap && b.y < a.maxY + gap
    }

    public func isValid(_ frame: CanvasFrame, sizes: [CanvasSize], others: [CanvasFrame]) -> Bool {
        isInside(frame) && frame.width > 0 && frame.height > 0
            && (sizes.isEmpty || sizes.contains { $0.allows(width: frame.width, height: frame.height) })
            && !others.contains { tooClose(frame, $0) }
    }

    public static func clampedUserScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, userScaleRange.lowerBound), userScaleRange.upperBound)
    }

    public static func scale(screenWidth: Double, availableHeight: Double, contentHeight: Double,
                             contentWidth: Double = 0, userScale: Double) -> Double {
        let automatic = min(max(screenWidth / referenceScreenWidth, automaticRange.lowerBound), automaticRange.upperBound)
        var wanted = automatic * clampedUserScale(userScale)
        if contentHeight > 0 { wanted = min(wanted, availableHeight / contentHeight) }
        if contentWidth > 0 { wanted = min(wanted, screenWidth / contentWidth) }
        return wanted
    }

    public func snapMove(_ proposed: CanvasFrame, others: [CanvasFrame]) -> CanvasFrame {
        var frame = proposed
        frame.x = snap(frame.x, to: startCandidates(length: frame.width, page: width, others: others.map { ($0.x, $0.maxX) }))
        frame.y = snap(frame.y, to: startCandidates(length: frame.height, page: height, others: others.map { ($0.y, $0.maxY) }))
        frame.x = frame.x.rounded()
        frame.y = frame.y.rounded()
        return frame
    }

    public func snapResize(_ frame: CanvasFrame, sizes: [CanvasSize], proposedWidth: Double, proposedHeight: Double,
                           others: [CanvasFrame]) -> CanvasFrame {
        let size: CanvasSize
        if let nearest = sizes.min(by: { abs($0.height - proposedHeight) < abs($1.height - proposedHeight) }) {
            size = nearest
        } else {
            let free = CanvasSize(minWidth: 1, maxWidth: width, height: max(1, proposedHeight.rounded()))
            var result = frame
            result.width = min(max(proposedWidth, 1), width).rounded()
            result.height = snap(free.height, to: [height - frame.y] + others.flatMap { [$0.y - gap - frame.y, $0.maxY - frame.y] })
            result.width = snap(result.width, to: [width - frame.x] + others.flatMap { [$0.x - gap - frame.x, $0.maxX - frame.x] })
            return CanvasFrame(x: frame.x.rounded(), y: frame.y.rounded(), width: result.width, height: result.height)
        }
        var newWidth = min(max(proposedWidth, size.minWidth), size.maxWidth)
        if size.isFlexible {
            var candidates = [width - frame.x]
            for other in others {
                candidates += [other.x - gap - frame.x, other.maxX - frame.x]
            }
            let free = newWidth
            newWidth = snap(newWidth, to: candidates.filter { $0 >= size.minWidth && $0 <= size.maxWidth })
            if newWidth == free {
                newWidth = abs(newWidth - size.minWidth) < 0.5 ? size.minWidth
                    : abs(newWidth - size.maxWidth) < 0.5 ? size.maxWidth : newWidth.rounded()
            }
            newWidth = min(max(newWidth, size.minWidth), size.maxWidth)
        }
        return CanvasFrame(x: frame.x.rounded(), y: frame.y.rounded(), width: newWidth, height: size.height)
    }

    public func firstFreeFrame(width w: Double, height h: Double, others: [CanvasFrame]) -> CanvasFrame? {
        var xs: Set<Double> = [0]
        var ys: Set<Double> = [0]
        for other in others {
            xs.insert(other.maxX + gap)
            ys.insert(other.maxY + gap)
        }
        for y in ys.sorted() {
            for x in xs.sorted() {
                let frame = CanvasFrame(x: x, y: y, width: w, height: h)
                if isValid(frame, sizes: [], others: others) { return frame }
            }
        }
        return nil
    }

    public func dropFrame(width w: Double, height h: Double, x: Double, y: Double, others: [CanvasFrame]) -> CanvasFrame {
        snapMove(CanvasFrame(x: x - w / 2, y: y - h / 2, width: w, height: h), others: others)
    }

    func startCandidates(length: Double, page: Double, others: [(start: Double, end: Double)]) -> [Double] {
        var result = [0, page - length]
        for other in others {
            result += [other.start, other.end - length, other.end + gap, other.start - gap - length]
        }
        return result
    }

    func snap(_ value: Double, to candidates: [Double]) -> Double {
        guard let best = candidates.min(by: { abs($0 - value) < abs($1 - value) }), abs(best - value) < snapDistance else { return value }
        return best
    }
}
