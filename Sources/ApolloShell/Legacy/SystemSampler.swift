import Darwin
import Foundation
import ApolloShellCore

/// Liest CPU, Arbeitsspeicher und Festplatte fuer die Ressourcen-Ringe des
/// Dashboards. Alles oeffentliche Mach-/Foundation-Schnittstellen, keine
/// Freigabe noetig.
enum SystemSampler {
    /// mach_host_self() einmal holen: jeder Aufruf belegt sonst einen neuen
    /// Port-Verweis.
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
        // Reihenfolge laut <mach/machine.h>: USER, SYSTEM, IDLE, NICE.
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    /// "Belegter Speicher" wie in der Aktivitaetsanzeige, grob: aktiv +
    /// fest verdrahtet + komprimiert.
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

    /// Startvolume: belegt = gesamt - fuer Wichtiges verfuegbar (das zaehlt
    /// auch loeschbare Caches als frei, wie der Finder).
    static func storage() -> (used: UInt64, total: UInt64)? {
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
