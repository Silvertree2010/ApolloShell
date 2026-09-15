import Foundation

/// CPU-Ticks aus host_statistics(HOST_CPU_LOAD_INFO), summiert ueber alle Kerne.
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

/// Rechnungen fuer die Ressourcen-Ringe des Dashboards (CPU, RAM, Speicher).
public enum ResourceMath {
    /// Auslastung zwischen zwei Messungen (0...1). Die Ticks zaehlen seit
    /// dem Start hoch, aussagekraeftig ist nur die Differenz. `nil`, wenn
    /// dazwischen nichts gezaehlt wurde (oder die Zaehler zurueckliefen).
    public static func cpuUsage(from old: CPUTicks, to new: CPUTicks) -> Double? {
        guard new.user >= old.user, new.system >= old.system,
              new.idle >= old.idle, new.nice >= old.nice
        else { return nil }
        let busy = (new.user - old.user) + (new.system - old.system) + (new.nice - old.nice)
        let total = busy + (new.idle - old.idle)
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }

    /// Anteil belegt, auf 0...1 begrenzt.
    public static func fraction(used: UInt64, total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }
}
