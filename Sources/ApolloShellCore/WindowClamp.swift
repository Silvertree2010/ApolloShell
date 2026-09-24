import CoreGraphics

public enum WindowClamp {
    public static let tolerance: CGFloat = 0.5

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

    public static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func isSameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

public struct ClampLedger<Key: Hashable> {
    public var maxAttempts: Int
    public var period: Double

    private var lastFrames: [Key: CGRect] = [:]
    private var attempts: [Key: [Double]] = [:]

    public init(maxAttempts: Int = 3, period: Double = 5) {
        self.maxAttempts = maxAttempts
        self.period = period
    }

    public mutating func shouldClamp(_ key: Key, current: CGRect, now: Double) -> Bool {
        if let last = lastFrames[key], WindowClamp.isSameFrame(last, current) {
            return false
        }
        let recent = (attempts[key] ?? []).filter { now - $0 < period }
        attempts[key] = recent.isEmpty ? nil : recent
        return recent.count < maxAttempts
    }

    public mutating func record(_ key: Key, result: CGRect, now: Double) {
        lastFrames[key] = result
        attempts[key, default: []].append(now)
    }

    public mutating func forget(_ key: Key) {
        lastFrames[key] = nil
        attempts[key] = nil
    }

    public mutating func forget(where predicate: (Key) -> Bool) {
        for key in lastFrames.keys where predicate(key) { lastFrames[key] = nil }
        for key in attempts.keys where predicate(key) { attempts[key] = nil }
    }

    public var count: Int { Set(lastFrames.keys).union(attempts.keys).count }
}
