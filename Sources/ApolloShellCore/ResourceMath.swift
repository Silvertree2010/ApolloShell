import Foundation

/// CPU ticks from host_statistics(HOST_CPU_LOAD_INFO), summed across all cores.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// Calculations for the resource rings of the dashboard (CPU, RAM, storage).
public enum ResourceMath {
    /// Usage between two measurements (0...1). The ticks count up since
    /// startup, only the difference is meaningful. `nil` if
    /// nothing was counted in between (or the counters wrapped around).
    public static func cpuUsage(from old: CPUTicks, to new: CPUTicks) -> Double? {
        guard new.user >= old.user, new.system >= old.system,
              new.idle >= old.idle, new.nice >= old.nice
        else { return nil }
        let busy = (new.user - old.user) + (new.system - old.system) + (new.nice - old.nice)
        let total = busy + (new.idle - old.idle)
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }

    /// Fraction used, clamped to 0...1.
    public static func fraction(used: UInt64, total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }
}
