import Darwin
import Foundation
import ApolloShellCore

/// Reads CPU, memory and disk for the resource rings of the
/// dashboard. All public Mach/Foundation interfaces, no
/// permission needed.
enum SystemSampler {
    /// Fetch mach_host_self() once: otherwise every call would take up a new
    /// port reference.
    private static let host = mach_host_self()

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // Order per <mach/machine.h>: USER, SYSTEM, IDLE, NICE.
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    /// "Memory used" as in Activity Monitor, roughly: active +
    /// wired + compressed.
    static func memory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (used, ProcessInfo.processInfo.physicalMemory)
    }

    /// How long a reading of the boot volume is reused. Asking the file
    /// system costs a synchronous round trip on the main thread (measured
    /// 20.09.: the single most expensive thing in the dashboard's per-second
    /// refresh), and a disk does not fill up within a second.
    private static let storageMaxAge: TimeInterval = 20
    private nonisolated(unsafe) static var storageCache: (value: (used: UInt64, total: UInt64), read: Date)?

    /// Boot volume: used = total - available for important usage (this counts
    /// deletable caches as free too, just like Finder does). Cached for
    /// `storageMaxAge`.
    static func storage() -> (used: UInt64, total: UInt64)? {
        if let cache = storageCache, Date().timeIntervalSince(cache.read) < storageMaxAge {
            return cache.value
        }
        let fresh = readStorage()
        if let fresh { storageCache = (fresh, Date()) }
        return fresh
    }

    private static func readStorage() -> (used: UInt64, total: UInt64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage,
              total > 0
        else { return nil }
        let totalBytes = UInt64(total)
        return (totalBytes - min(UInt64(max(free, 0)), totalBytes), totalBytes)
    }
}
