import Foundation

public struct BlockMeter: Sendable {
    private var start: UInt64?
    private var longest: UInt64 = 0

    public init() {}

    public mutating func began(at time: UInt64) {
        start = time
    }

    public mutating func ended(at time: UInt64) {
        guard let start, time >= start else { return }
        longest = max(longest, time - start)
        self.start = nil
    }

    public mutating func take(now: UInt64) -> Double {
        var result = longest
        if let start, now >= start {
            result = max(result, now - start)
            self.start = now
        }
        longest = 0
        return Double(result) / 1_000_000
    }
}
