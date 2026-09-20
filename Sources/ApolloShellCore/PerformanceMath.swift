import Foundation

// MARK: - Network

/// The summed byte counters of the counted network interfaces since the
/// system start. 64 bits out of if_data64 (sysctl NET_RT_IFLIST2): the
/// counters of getifaddrs are only 32 bits and start at zero again after 4 GB.
public struct NetCounters: Equatable, Sendable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }

    public static let zero = NetCounters(received: 0, sent: 0)
}

/// The data rate in bytes per second.
public struct NetRate: Equatable, Sendable {
    public var download: Double
    public var upload: Double

    public init(download: Double, upload: Double) {
        self.download = download
        self.upload = upload
    }
}

public enum NetworkMath {
    /// Which interfaces go into the sum. Not among them: loopback (lo0, whose
    /// traffic never leaves the Mac), point-to-point tunnels (utun: VPNs like
    /// Tailscale or Mullvad - their traffic runs over en0 a second time,
    /// encrypted; measured 14.09.: utun6 1.0 GB in, en0 3.8 GB, and the sum
    /// would have shown a quarter too much) and bridges (bridge0 counts the
    /// packets of its members en1/en2 again).
    public static func counts(flags: Int32, type: UInt8) -> Bool {
        if flags & IFF_LOOPBACK != 0 { return false }
        if flags & IFF_POINTOPOINT != 0 { return false }
        return Int32(type) != IFT_BRIDGE
    }

    /// The difference between two measurements. `nil` when a counter became
    /// smaller: then an interface fell away (a VPN off, an adapter unplugged)
    /// - the difference would be nonsense, and with UInt64 even an overflow.
    public static func delta(from old: NetCounters, to new: NetCounters) -> NetCounters? {
        guard new.received >= old.received, new.sent >= old.sent else { return nil }
        return NetCounters(received: new.received - old.received, sent: new.sent - old.sent)
    }

    /// The rate between two measurements; `nil` with a reset counter or when
    /// no time lies between them.
    public static func rate(from old: NetCounters, to new: NetCounters, seconds: TimeInterval) -> NetRate? {
        guard seconds > 0, let delta = delta(from: old, to: new) else { return nil }
        return NetRate(download: Double(delta.received) / seconds, upload: Double(delta.sent) / seconds)
    }
}

/// The rate and the total out of running counter readings.
///
/// The total counts from the first measurement on and across pauses too (the
/// counters of the system go on running). The rate does not: averaged across a
/// pause it would be wrong, so the first measurement after one gives none.
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

// MARK: - History

/// The last `capacity` readings, the oldest first - for the history lines.
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

/// The points of the history line in the unit square (x from the left, y from the bottom).
public enum Sparkline {
    /// The upper end of the y axis: the maximum in the history, but never
    /// below `floor`. Without a floor, an idle trickle of 200 B/s would fill
    /// the whole height and look like full load.
    public static func scale(peak: Double, floor: Double) -> Double {
        max(peak, floor)
    }

    /// Flush right: the newest value always stands at the right edge; while
    /// the buffer is not full, the line grows in from the right - so every
    /// point moves by exactly one step per measurement.
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

// MARK: - Texts

/// Byte entries with the decimal separator of the language ("1,2 MB" in
/// German, "1.2 MB" in English), a space before the unit.
public enum ByteFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    /// Decimal (1 KB = 1000 B) as in the Finder and Activity Monitor for the
    /// network; `binary` (1024) for memory - otherwise 24 GB of RAM would
    /// stand there as "26 GB". Below 10 one decimal ("1.2 MB"), above it whole
    /// numbers ("340 KB"): the width stays calm.
    public static func bytes(_ value: Double, binary: Bool = false, locale: Locale = .current) -> String {
        let base: Double = binary ? 1024 : 1000
        var amount = value.isFinite ? max(value, 0) : 0
        var unit = 0
        // Round first, then choose the unit: otherwise 999.7 KB would be "1000 KB".
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

    /// The data rate, "1.2 MB/s" for instance.
    public static func rate(_ bytesPerSecond: Double, locale: Locale = .current) -> String {
        bytes(bytesPerSecond, locale: locale) + "/s"
    }

    /// "412 GB of 994 GB".
    public static func usage(used: UInt64, total: UInt64, binary: Bool = false, locale: Locale = .current) -> String {
        let used = bytes(Double(used), binary: binary, locale: locale)
        let total = bytes(Double(total), binary: binary, locale: locale)
        return String(localized: "\(used) of \(total)")
    }

    /// The value the way it would be shown after rounding.
    private static func shown(_ amount: Double, unit: Int) -> Double {
        unit == 0 || amount >= 9.95 ? amount.rounded() : (amount * 10).rounded() / 10
    }
}

public enum PerformanceText {
    /// The share as "37 %"; without a reading a dash instead of a wrong zero.
    public static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return "–" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded())) %"
    }
}

/// The texts and the level for the battery gauge.
public enum BatteryTankText {
    /// The fill height 0...1.
    public static func fill(_ state: BatteryState) -> Double {
        min(max(Double(state.level) / 100, 0), 1)
    }

    public static func percent(_ state: BatteryState) -> String {
        "\(min(max(state.level, 0), 100)) %"
    }

    /// `minutes`: to full (while charging) or to empty (on battery), the way
    /// IOKit reports them. Zero or negative means "still being worked out".
    public static func status(_ state: BatteryState, minutes: Int?) -> String {
        let time = minutes.flatMap { $0 > 0 ? UptimeText.format(seconds: TimeInterval($0) * 60) : nil }
        if state.charging { return time.map { String(localized: "Full in \($0)") } ?? String(localized: "Charging") }
        if state.onAC { return state.level >= 100 ? String(localized: "Charged") : String(localized: "On Power Adapter") }
        return time.map { String(localized: "\($0) Left") } ?? String(localized: "Calculating…")
    }
}
