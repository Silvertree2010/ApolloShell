import Foundation

public struct NetCounters: Equatable, Sendable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }

    public static let zero = NetCounters(received: 0, sent: 0)
}

public struct NetRate: Equatable, Sendable {
    public var download: Double
    public var upload: Double

    public init(download: Double, upload: Double) {
        self.download = download
        self.upload = upload
    }
}

public enum NetworkMath {
    #if canImport(Darwin)
    public static func counts(flags: Int32, type: UInt8) -> Bool {
        if flags & IFF_LOOPBACK != 0 { return false }
        if flags & IFF_POINTOPOINT != 0 { return false }
        return Int32(type) != IFT_BRIDGE
    }
    #endif

    public static func delta(from old: NetCounters, to new: NetCounters) -> NetCounters? {
        guard new.received >= old.received, new.sent >= old.sent else { return nil }
        return NetCounters(received: new.received - old.received, sent: new.sent - old.sent)
    }

    public static func rate(from old: NetCounters, to new: NetCounters, seconds: TimeInterval) -> NetRate? {
        guard seconds > 0, let delta = delta(from: old, to: new) else { return nil }
        return NetRate(download: Double(delta.received) / seconds, upload: Double(delta.sent) / seconds)
    }
}

public struct NetworkMeter: Sendable {
    public private(set) var rate: NetRate?
    public private(set) var total = NetCounters.zero
    private var last: NetCounters?
    private var lastTime: TimeInterval = 0
    private var paused = true

    public init() {}

    public mutating func pause() {
        paused = true
        rate = nil
    }

    public mutating func add(_ counters: NetCounters, at time: TimeInterval) {
        defer {
            self.last = counters
            self.lastTime = time
            self.paused = false
        }
        guard let last, let delta = NetworkMath.delta(from: last, to: counters) else {
            rate = nil
            return
        }
        total.received += delta.received
        total.sent += delta.sent
        rate = paused ? nil : NetworkMath.rate(from: last, to: counters, seconds: time - lastTime)
    }
}

public struct SampleHistory: Equatable, Sendable {
    public let capacity: Int
    public private(set) var values: [Double] = []

    public init(capacity: Int) {
        precondition(capacity > 0, "Verlauf braucht Platz fuer mindestens einen Wert")
        self.capacity = capacity
    }

    public mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    public mutating func removeAll() {
        values.removeAll(keepingCapacity: true)
    }

    public var peak: Double { values.max() ?? 0 }
}

public enum Sparkline {
    public static func scale(peak: Double, floor: Double) -> Double {
        max(peak, floor)
    }

    public static func points(_ values: [Double], capacity: Int, scale: Double) -> [CGPoint] {
        guard capacity > 0, !values.isEmpty else { return [] }
        let shown = values.suffix(capacity)
        let step = capacity > 1 ? 1 / Double(capacity - 1) : 0
        let offset = capacity - shown.count
        return shown.enumerated().map { index, value in
            CGPoint(
                x: capacity > 1 ? Double(offset + index) * step : 1,
                y: scale > 0 ? min(max(value / scale, 0), 1) : 0
            )
        }
    }
}

public enum ByteFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    public static func bytes(_ value: Double, binary: Bool = false, locale: Locale = .current) -> String {
        let base: Double = binary ? 1024 : 1000
        var amount = value.isFinite ? max(value, 0) : 0
        var unit = 0
        while unit < units.count - 1, shown(amount, unit: unit) >= 1000 {
            amount /= base
            unit += 1
        }
        if unit == 0 { return "\(Int(amount.rounded())) B" }
        let tenths = Int((amount * 10).rounded())
        if tenths < 100 {
            return "\(tenths / 10)\(locale.decimalSeparator ?? ".")\(tenths % 10) \(units[unit])"
        }
        return "\(Int(amount.rounded())) \(units[unit])"
    }

    public static func rate(_ bytesPerSecond: Double, locale: Locale = .current) -> String {
        bytes(bytesPerSecond, locale: locale) + "/s"
    }

    public static func usage(used: UInt64, total: UInt64, binary: Bool = false, locale: Locale = .current) -> String {
        let used = bytes(Double(used), binary: binary, locale: locale)
        let total = bytes(Double(total), binary: binary, locale: locale)
        return String(localized: "\(used) of \(total)")
    }

    private static func shown(_ amount: Double, unit: Int) -> Double {
        unit == 0 || amount >= 9.95 ? amount.rounded() : (amount * 10).rounded() / 10
    }
}

public enum PerformanceText {
    public static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return "–" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded())) %"
    }
}

public enum BatteryTankText {
    public static func fill(_ state: BatteryState) -> Double {
        min(max(Double(state.level) / 100, 0), 1)
    }

    public static func percent(_ state: BatteryState) -> String {
        "\(min(max(state.level, 0), 100)) %"
    }

    public static func status(_ state: BatteryState, minutes: Int?) -> String {
        let time = minutes.flatMap { $0 > 0 ? UptimeText.format(seconds: TimeInterval($0) * 60) : nil }
        if state.charging { return time.map { String(localized: "Full in \($0)") } ?? String(localized: "Charging") }
        if state.onAC { return state.level >= 100 ? String(localized: "Charged") : String(localized: "On Power Adapter") }
        return time.map { String(localized: "\($0) Left") } ?? String(localized: "Calculating…")
    }
}
