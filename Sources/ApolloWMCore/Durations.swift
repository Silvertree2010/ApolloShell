import Foundation

public struct Durations: Sendable {
    public private(set) var samples: [Double] = []

    public init() {}

    public mutating func add(_ seconds: Double) { samples.append(seconds) }

    public var count: Int { samples.count }

    public func percentile(_ p: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up)) - 1
        return sorted[Swift.min(Swift.max(rank, 0), sorted.count - 1)]
    }

    public var median: Double? { percentile(0.5) }
    public var max: Double? { samples.max() }

    public var summary: String {
        guard let median, let p95 = percentile(0.95), let max else { return "n=0" }
        func ms(_ s: Double) -> String { String(format: "%.1fms", s * 1000) }
        return "n=\(count) median \(ms(median)) p95 \(ms(p95)) max \(ms(max))"
    }
}
